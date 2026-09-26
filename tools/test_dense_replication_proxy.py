from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).parent))
import tcp_link_proxy as proxy


class StreamLinkTests(unittest.TestCase):
    def test_independent_links_and_backpressure(self):
        link = proxy.StreamLink({'bytes_per_second': 1000, 'queue_seconds': 0.2}, 1)
        link.receive(0, ('down', 1), b'x' * 200, 'one')
        self.assertFalse(link.accepting(('down', 1)), 'a full link pauses reads instead of dropping')
        self.assertTrue(link.accepting(('down', 2)), 'other clients keep independent budgets')
        link.receive(0, ('down', 2), b'y' * 200, 'two')
        link.receive(0, ('up', 1), b'z' * 200, 'up')
        self.assertEqual(link.available[('down', 1)], 0.2)
        received = []
        link.deliver(0.199, lambda *args: received.append(args))
        self.assertEqual(received, [])
        link.deliver(0.2, lambda *args: received.append(args))
        self.assertEqual([row[2] for row in received], ['one', 'two', 'up'])
        self.assertEqual(link.counters['down']['delivered_bytes'], 400)
        self.assertTrue(link.accepting(('down', 1)), 'delivery releases backpressure')

    def test_loss_stalls_block_later_bytes(self):
        link = proxy.StreamLink({'loss': 1}, 2)
        link.receive(0, ('down', 1), b'stalled', 'client')
        link.receive(0.01, ('down', 1), b'behind', 'client', impaired=False)
        received = []
        link.deliver(0.1, lambda *args: received.append(args))
        self.assertEqual(received, [], 'healthy bytes still wait behind a retransmission')
        link.deliver(proxy.RETRANSMIT_STALL_SECONDS, lambda *args: received.append(args))
        self.assertEqual([row[1] for row in received], [b'stalled', b'behind'])
        self.assertEqual(link.counters['down']['loss_stalls'], 1)

    def test_jitter_never_reorders_a_link(self):
        link = proxy.StreamLink({'delay': 0.05, 'jitter': 0.05}, 5)
        for index in range(200):
            link.receive(index * 0.001, ('down', index % 3), bytes([index]), index % 3)
        received = []
        link.deliver(10.0, lambda *args: received.append(args))
        for connection in range(3):
            order = [row[1][0] for row in received if row[2] == connection]
            self.assertEqual(order, sorted(order))

    def test_hold_until_delays_delivery(self):
        link = proxy.StreamLink({}, 3)
        link.receive(0, ('up', 1), b'held', 'server', hold_until=0.5)
        received = []
        link.deliver(0.49, lambda *args: received.append(args))
        self.assertEqual(received, [])
        link.deliver(0.5, lambda *args: received.append(args))
        self.assertEqual(link.counters['up']['held'], 1)
        self.assertEqual(len(received), 1)

    def test_seeded_schedule_and_byte_accounting(self):
        links = [proxy.StreamLink({'delay': 0.05, 'jitter': 0.02, 'loss': 0.05}, 8) for _ in range(2)]
        for link in links:
            for i in range(100):
                link.receive(i * 0.001, ('down', i % 4), bytes(i), i % 4)
        self.assertEqual(links[0].queue, links[1].queue)
        self.assertEqual(links[0].counters, links[1].counters)
        self.assertEqual(links[0].counters['down']['received_bytes'], sum(range(100)))
        self.assertGreater(links[0].counters['down']['loss_stalls'], 0)


if __name__ == '__main__':
    unittest.main()
