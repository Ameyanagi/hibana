"""Validated per-workspace limits for exact dynamic-programming score cells."""

from std.io import Writable, Writer
from std.sys.info import size_of


comptime _CELL_BYTES = size_of[Int]()
comptime _MAX_CELLS = Int.MAX // _CELL_BYTES


struct WorkspaceBudget(Copyable, Equatable, ImplicitlyCopyable, Writable):
    """Maximum retained DP score cells in one exact matching workspace.

    Zero permits empty-query and rejected-subsequence fast paths only. The
    default permits any addressable score table; it is not a process memory
    limit. Callers handling external input should choose an application limit.
    The limit excludes prepared input, bonuses, result positions, heaps,
    allocator metadata, and transient old storage during reserve growth.

    Invariants are established at construction. Direct mutation of underscore
    fields is out of contract; ``validate`` provides an explicit checkpoint.
    """

    var _max_cells: Int

    def __init__(out self):
        self._max_cells = _MAX_CELLS

    def __init__(out self, *, max_cells: Int) raises:
        self._max_cells = max_cells
        self.validate()

    def validate(self) raises:
        if self._max_cells < 0 or self._max_cells > _MAX_CELLS:
            raise Error(
                String(
                    "WorkspaceBudget max_cells must be within [0, ",
                    _MAX_CELLS,
                    "]; got ",
                    self._max_cells,
                    "; choose a limit whose Int score-cell bytes fit in Int",
                )
            )

    def __eq__(self, other: Self) -> Bool:
        return self._max_cells == other._max_cells

    def write_to[W: Writer](self, mut writer: W):
        writer.write("WorkspaceBudget(max_cells=", self._max_cells, ")")

    def max_cells(self) -> Int:
        """Return the configured cell limit without revalidating storage."""
        return self._max_cells

    def max_bytes(self) -> Int:
        """Return the corresponding score-table payload byte limit."""
        return self._max_cells * _CELL_BYTES

    def required_cells(self, pattern_count: Int, candidate_count: Int) raises -> Int:
        """Check nonnegative dimensions, cell/byte overflow, and this budget.

        This method allocates no score table, so callers can inspect synthetic
        boundary dimensions without constructing enormous strings or buffers.
        """
        if pattern_count < 0:
            raise Error(String("pattern_count must be >= 0; got ", pattern_count))
        if candidate_count < 0:
            raise Error(String("candidate_count must be >= 0; got ", candidate_count))
        return self._required_cells(pattern_count, candidate_count)

    def _required_cells(self, pattern_count: Int, candidate_count: Int) raises -> Int:
        """Check dimensions already known to be nonnegative storage lengths."""
        debug_assert(pattern_count >= 0 and candidate_count >= 0)
        if candidate_count != 0 and pattern_count > Int.MAX // candidate_count:
            raise Error(
                String(
                    "exact DP requires ",
                    pattern_count,
                    " * ",
                    candidate_count,
                    " cells; cell count exceeds Int.MAX; allowed ",
                    self._max_cells,
                    " cells; shorten the query or candidate",
                )
            )
        var required = pattern_count * candidate_count
        if required > _MAX_CELLS:
            raise Error(
                String(
                    "exact DP requires ",
                    required,
                    " cells * ",
                    _CELL_BYTES,
                    " bytes; byte count exceeds Int.MAX; allowed ",
                    self._max_cells,
                    " cells (",
                    self.max_bytes(),
                    " bytes); shorten the query or candidate",
                )
            )
        if required > self._max_cells:
            raise Error(
                String(
                    "exact DP requires ",
                    required,
                    " cells (",
                    required * _CELL_BYTES,
                    " bytes); allowed ",
                    self._max_cells,
                    " cells (",
                    self.max_bytes(),
                    " bytes); shorten the query or candidate, or increase max_cells",
                )
            )
        return required
