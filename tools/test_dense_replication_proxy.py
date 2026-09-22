import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('dense_proxy', Path(__file__).with_name('verify-dense-replication.py'))
proxy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(proxy)


class DenseProxyTests(unittest.TestCase):
    def test_independent_links_and_tail_drop(self):
        queue = proxy.LinkQueue({'bytes_per_second': 1000, 'queue_seconds': 0.2}, 1)
        queue.receive(0, ('down', 1), b'x' * 200, 'one')
        queue.receive(0, ('down', 1), b'x', 'dropped')
        queue.receive(0, ('down', 2), b'y' * 200, 'two')
        queue.receive(0, ('up', 1), b'z' * 200, 'up')
        self.assertEqual(queue.counters['down']['congestion_drops'], 1)
        self.assertEqual(queue.available[('down', 1)], 0.2)
        received = []
        queue.deliver(0.199, lambda *args: received.append(args))
        self.assertEqual(received, [])
        queue.deliver(0.2, lambda *args: received.append(args))
        self.assertEqual([row[2] for row in received], ['one', 'two', 'up'])
        self.assertEqual(queue.counters['down']['delivered_bytes'], 400)

    def test_loss_and_healthy_settlement(self):
        queue = proxy.LinkQueue({'loss': 1}, 2)
        queue.receive(0, ('down', 1), b'lost', 'client')
        queue.receive(0, ('down', 1), b'recovery', 'client', impaired=False)
        received = []
        queue.deliver(0, lambda *args: received.append(args))
        self.assertEqual(received, [('down', b'recovery', 'client')])
        self.assertEqual(queue.counters['down']['loss_drops'], 1)

    def test_seeded_schedule_and_byte_accounting(self):
        queues = [proxy.LinkQueue(proxy.PROFILES['loss_jitter'], 8) for _ in range(2)]
        for queue in queues:
            for i in range(100):
                queue.receive(i * 0.001, ('down', i % 4), bytes(i), i % 4)
        self.assertEqual(queues[0].queue, queues[1].queue)
        self.assertEqual(queues[0].counters, queues[1].counters)
        self.assertEqual(queues[0].counters['down']['received_bytes'], sum(range(100)))
        self.assertGreater(queues[0].counters['down']['loss_drops'], 0)


if __name__ == '__main__':
    unittest.main()
