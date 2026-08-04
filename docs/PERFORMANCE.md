# Performance

## Measured behaviour

On a generated 200,000-commit repository (40 branches, 8% merge rate, commit-graph
written), on a single developer machine:

| Metric | Measured | Target |
|---|---|---|
| Time to first painted rows | **331 ms** | < 500 ms |
| Full graph built in background | **629 ms** | < 3 s |
| Memory for the graph | **124 bytes/commit** (≈59 MB projected at 500k) | ≤ 64 MB |
| First-parent chains that stay straight | **199,960 / 199,960** | all |
| Row order vs `git rev-list --topo-order` | **exact match** | exact match |

Reproduce with `gbm_graph_check`:

```bash
R=/tmp/fixture
git init --quiet --bare $R/.git && git -C $R config core.bare false
./build/dev/tests/gen_history --commits 200000 --branches 40 --merge-rate 0.08 \
    --octopus 3 --tags 500 --seed 42 | git -C $R fast-import --quiet
git -C $R commit-graph write --reachable --changed-paths

./build/dev/tests/gbm_graph_check $R --print-rows 40
```

`gen_history` emits a `git fast-import` stream, so the 200k-commit fixture takes
about a minute instead of hours and needs no checkout. `gbm_graph_check` verifies
the row order against Git, checks the layout invariants, prints the timings above,
and can render the first N rows as ASCII. It works the same on a real clone — a
large, long-lived open-source repository is the best test there is.

One caveat on that fixture, so the numbers are not read as more flattering than they
are: it merges randomly across the whole history, which is far more tangled than
real repositories, where merges are usually local. It therefore hits the 48-lane
render cap and pushes about 12% of edges into the overflow gutter. For comparison,
`git log --graph` needs *more* columns than we use on the same input (51 vs 31 on a
4-branch variant), so the width is a property of the topology rather than of the
lane allocator.

## Repository performance settings

`commit-graph` and `multi-pack-index` are the difference between a fast browse and a
slow one, but they write into your repository, so the app asks first and remembers
your answer:

```bash
git commit-graph write --reachable --changed-paths --split
git multi-pack-index write --bitmap
git config feature.manyFiles true      # index v4
git config core.fsmonitor true         # git >= 2.37; huge win for status
git config core.untrackedCache true
```
