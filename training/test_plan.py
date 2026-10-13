"""Tests for the incremental-training batch plan (run: python3 -m unittest training/test_plan.py)."""
import unittest
from plan import bucket_of, make_plan


class BucketTest(unittest.TestCase):
    def test_rounds_up_to_64_with_a_floor_and_cap(self):
        self.assertEqual(bucket_of(10), 128)
        self.assertEqual(bucket_of(129), 192)
        self.assertEqual(bucket_of(192), 192)
        self.assertEqual(bucket_of(450), 512)
        self.assertEqual(bucket_of(900, cap=640), 640)


class PlanTest(unittest.TestCase):
    lengths = [100] * 37 + [200] * 50 + [300] * 9 + [500] * 3

    def plan(self, **kw):
        args = dict(batch=8, epochs=2, seed=7)
        args.update(kw)
        return make_plan(self.lengths, **args)

    def test_batches_are_full_and_single_bucket(self):
        for b in self.plan():
            self.assertEqual(len(b), 8)
            self.assertEqual(len({bucket_of(self.lengths[i]) for i in b}), 1)

    def test_every_example_is_seen_each_epoch(self):
        plan = self.plan(epochs=1)
        self.assertEqual({i for b in plan for i in b}, set(range(len(self.lengths))))

    def test_deterministic_so_a_resumed_run_continues_exactly(self):
        self.assertEqual(self.plan(), self.plan())
        self.assertNotEqual(self.plan(seed=1), self.plan(seed=2))

    def test_epochs_are_shuffled_differently(self):
        plan = self.plan(epochs=2)
        half = len(plan) // 2
        self.assertNotEqual(plan[:half], plan[half:])

    def test_small_buckets_still_make_full_batches(self):
        plan = make_plan([500] * 3, batch=8, epochs=1, seed=0)
        self.assertEqual(len(plan), 1)
        self.assertEqual(len(plan[0]), 8)


if __name__ == "__main__":
    unittest.main()
