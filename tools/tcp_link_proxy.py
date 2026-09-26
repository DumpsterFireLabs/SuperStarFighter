"""Loopback TCP stream proxy that impairs real game connections in both directions.

A byte stream cannot drop, reorder or duplicate data without corrupting it, so
faults are modelled as TCP presents them to the application: propagation delay
and jitter that never reorder bytes, loss as a retransmission stall that also
blocks every later byte (head-of-line), blackouts as held delivery, and limited
bandwidth as serialization plus reader backpressure rather than tail drops.
"""
import errno
import heapq
import random
import select
import socket
import time

RETRANSMIT_STALL_SECONDS = 0.200
CONNECT_TIMEOUT_SECONDS = 5.0
CONNECT_PENDING = {0, errno.EINPROGRESS, errno.EWOULDBLOCK, getattr(errno, 'WSAEWOULDBLOCK', errno.EWOULDBLOCK)}
DEFAULT_BACKLOG_BYTES = 1 << 20
READ_BYTES = 65536


class StreamLink:
    """Order-preserving delivery schedule for independent (direction, connection) links."""

    def __init__(self, profile, seed):
        self.profile, self.rng = profile, random.Random(seed)
        self.available, self.last_delivery, self.backlog = {}, {}, {}
        self.queue = []
        self.serial = self.peak = 0
        self.counters = {d: dict(received=0, received_bytes=0, delivered=0, delivered_bytes=0,
                                 delayed=0, loss_stalls=0, held=0, backpressure_pauses=0,
                                 bandwidth_wait_seconds=0.0, max_queue_wait_seconds=0.0)
                         for d in ('up', 'down')}

    def backlog_limit(self, impaired=True):
        profile = self.profile if impaired else {}
        if profile.get('bytes_per_second') and profile.get('queue_seconds'):
            return max(1, int(profile['bytes_per_second'] * profile['queue_seconds']))
        return DEFAULT_BACKLOG_BYTES

    def accepting(self, key, impaired=True):
        return self.backlog.get(key, 0) < self.backlog_limit(impaired)

    def receive(self, now, key, data, destination, impaired=True, hold_until=0.0):
        direction = key[0]
        row = self.counters[direction]
        row['received'] += 1
        row['received_bytes'] += len(data)
        profile = self.profile if impaired else {}
        # Honor bandwidth already reserved when the healthy settlement begins.
        finish = max(now, self.available.get(key, now))
        if profile.get('bytes_per_second'):
            finish += len(data) / profile['bytes_per_second']
            row['bandwidth_wait_seconds'] += finish - now
        self.available[key] = finish
        row['max_queue_wait_seconds'] = max(row['max_queue_wait_seconds'], finish - now)
        delay = max(0.0, profile.get('delay', 0) + self.rng.uniform(-1, 1) * profile.get('jitter', 0))
        if self.rng.random() < profile.get('loss', 0):
            row['loss_stalls'] += 1
            delay += RETRANSMIT_STALL_SECONDS
        deliver_at = finish + delay
        if hold_until > deliver_at:
            row['held'] += 1
            deliver_at = hold_until
        # A stream never overtakes earlier bytes on the same link.
        deliver_at = max(deliver_at, self.last_delivery.get(key, 0.0))
        self.last_delivery[key] = deliver_at
        if deliver_at > now:
            row['delayed'] += 1
        self.serial += 1
        heapq.heappush(self.queue, (deliver_at, self.serial, key, data, destination))
        self.backlog[key] = self.backlog.get(key, 0) + len(data)
        self.peak = max(self.peak, len(self.queue))

    def deliver(self, now, sender):
        while self.queue and self.queue[0][0] <= now:
            _, _, key, data, destination = heapq.heappop(self.queue)
            self.backlog[key] -= len(data)
            sender(key[0], data, destination)
            self.counters[key[0]]['delivered'] += 1
            self.counters[key[0]]['delivered_bytes'] += len(data)


class StreamProxy:
    """Accepts loopback clients on listen_port and relays each to target_port."""

    def __init__(self, listen_port, target_port, link, max_connections):
        self.target_port, self.link, self.max_connections = target_port, link, max_connections
        # Never bind an externally reachable interface or modify host networking.
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.listener.bind(('127.0.0.1', listen_port))
        self.listener.listen(64)
        self.listener.setblocking(False)
        self.peer = {}      # socket -> opposite socket
        self.route = {}     # socket -> (direction of bytes read from it, connection id)
        self.outbound = {}  # socket -> pending bytes
        self.connecting = {}  # upstream socket -> (client socket, connect started)
        self.draining = {}  # destination socket -> link key whose source reached EOF
        self.accepted = 0          # connections relayed to the target
        self.refused = 0           # target refusals passed back to the client
        self.peak_connections = 0  # concurrent relayed connections
        self.downstream_listeners = []

    def close(self):
        pending = [sock for pair in self.connecting.items() for sock in (pair[0], pair[1][0])]
        for sock in list(self.peer) + pending + [self.listener]:
            sock.close()
        self.peer.clear()
        self.connecting.clear()

    def _accept(self):
        while True:
            try:
                client, _ = self.listener.accept()
            except BlockingIOError:
                return
            self._relay(client)

    def _relay(self, client):
        if len(self.peer) // 2 + len(self.connecting) >= self.max_connections:
            client.close()
            raise RuntimeError('unexpected extra client')
        # Connect without blocking so a backlogged target never stalls other links.
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setblocking(False)
        if server.connect_ex(('127.0.0.1', self.target_port)) not in CONNECT_PENDING:
            self._refuse(client, server)
            return
        self.connecting[server] = (client, time.monotonic())

    def _refuse(self, client, server):
        # Mirror the target's refusal so the client's own retry path runs.
        self.refused += 1
        client.close()
        server.close()

    def _finish_connect(self, server, failed):
        client, _ = self.connecting.pop(server)
        if failed or server.getsockopt(socket.SOL_SOCKET, socket.SO_ERROR):
            self._refuse(client, server)
            return
        for sock in (client, server):
            sock.setblocking(False)
            try:
                sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            except OSError:
                pass  # macOS rejects this on a socket its peer already reset.
            self.outbound[sock] = bytearray()
        connection_id = self.accepted
        self.accepted += 1
        self.peer[client], self.peer[server] = server, client
        self.route[client], self.route[server] = ('up', connection_id), ('down', connection_id)
        self.peak_connections = max(self.peak_connections, len(self.peer) // 2)

    def _close_pair(self, sock):
        other = self.peer.pop(sock, None)
        self.route.pop(sock, None)
        self.outbound.pop(sock, None)
        self.draining.pop(sock, None)
        sock.close()
        if other is not None:
            self.peer.pop(other, None)
            self.route.pop(other, None)
            self.outbound.pop(other, None)
            self.draining.pop(other, None)
            other.close()

    def _begin_drain(self, sock):
        # A FIN arrives after every earlier byte, so deliver what the link still
        # holds for the other side before closing the pair.
        key = self.route.pop(sock)
        self.draining[self.peer[sock]] = key

    def _close_drained(self):
        for destination, key in list(self.draining.items()):
            if destination not in self.outbound:
                self.draining.pop(destination, None)
            elif self.link.backlog.get(key, 0) == 0 and not self.outbound[destination]:
                self._close_pair(destination)

    def _send(self, direction, data, destination):
        if destination in self.outbound:
            self.outbound[destination] += data
            if direction == 'down':
                for listener in self.downstream_listeners:
                    listener(len(data))

    def poll(self, now, timeout, impaired=True, hold_until=None):
        """hold_until maps direction -> monotonic time before which bytes are held."""
        hold_until = hold_until or {}
        readable_candidates = [self.listener]
        for sock, key in self.route.items():
            if self.link.accepting(key, impaired):
                readable_candidates.append(sock)
            else:
                self.link.counters[key[0]]['backpressure_pauses'] += 1
        writable_candidates = [sock for sock, pending in self.outbound.items() if pending]
        connecting = list(self.connecting)
        # Windows reports a refused non-blocking connect as exceptional, not writable.
        readable, writable, exceptional = select.select(readable_candidates, writable_candidates + connecting, connecting, timeout)
        for server in connecting:
            if server in writable or server in exceptional:
                self._finish_connect(server, server in exceptional)
            elif time.monotonic() - self.connecting[server][1] > CONNECT_TIMEOUT_SECONDS:
                client, _ = self.connecting.pop(server)
                self._refuse(client, server)
        for sock in readable:
            if sock is self.listener:
                self._accept()
                continue
            if sock not in self.route:
                continue
            try:
                data = sock.recv(READ_BYTES)
            except (BlockingIOError, InterruptedError):
                continue
            except ConnectionError:
                self._close_pair(sock)
                continue
            if not data:
                self._begin_drain(sock)
                continue
            key = self.route[sock]
            self.link.receive(now, key, data, self.peer[sock], impaired, hold_until.get(key[0], 0.0))
        self.link.deliver(now, self._send)
        for sock in writable:
            if sock in connecting:
                continue
            pending = self.outbound.get(sock)
            if not pending:
                continue
            try:
                sent = sock.send(pending)
            except (BlockingIOError, InterruptedError):
                continue
            except ConnectionError:
                self._close_pair(sock)
                continue
            del pending[:sent]
        self._close_drained()
