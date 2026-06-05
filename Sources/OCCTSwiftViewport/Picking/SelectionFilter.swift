// SelectionFilter.swift
// ViewportKit
//
// Composable predicate over pick results — a SelectMgr_Filter analogue.

import Foundation

/// A composable predicate that decides whether a `PickResult` is accepted as a
/// selection.
///
/// This is the OCCTSwiftViewport analogue of OCCT's `SelectMgr_Filter` chain.
/// Where OCCT filters sensitive entities before sorting, here the GPU pick pass
/// has already resolved a single primitive, so a `SelectionFilter` runs on the
/// decoded `PickResult` and either accepts it or rejects it. A rejected pick is
/// treated as a miss — GPU picking reads exactly one primitive per pixel, so
/// there is no alternate candidate to fall through to.
///
/// Assign one to `ViewportController.selectionFilter` to constrain what the
/// user-geometry pick stream surfaces (e.g. "edges only", "everything except
/// the construction body"). Widget-layer picks bypass the filter — that stream
/// is owned by an external consumer (e.g. OCCTSwiftAIS manipulators).
///
/// Filters compose:
/// ```swift
/// controller.selectionFilter = .edges.or(.vertices)
///                                    .and(.excludingBodyIDs(["grid"]))
/// ```
///
/// - Note: Depth/distance filtering is intentionally absent: the GPU pick
///   `PickResult` carries no depth value. Use the CPU `SceneRaycast` path if you
///   need distance-aware filtering.
public struct SelectionFilter: Sendable {

    private let predicate: @Sendable (PickResult) -> Bool

    /// Wraps an arbitrary predicate.
    public init(_ predicate: @escaping @Sendable (PickResult) -> Bool) {
        self.predicate = predicate
    }

    /// Returns `true` if the result passes this filter.
    public func matches(_ result: PickResult) -> Bool {
        predicate(result)
    }

    /// Lets a filter be called like a function: `filter(result)`.
    public func callAsFunction(_ result: PickResult) -> Bool {
        predicate(result)
    }
}

// MARK: - Built-in filters

extension SelectionFilter {

    /// Accepts every result.
    public static let all = SelectionFilter { _ in true }

    /// Rejects every result.
    public static let nothing = SelectionFilter { _ in false }

    /// Accepts results of a single sub-shape kind.
    public static func kind(_ kind: PrimitiveKind) -> SelectionFilter {
        SelectionFilter { $0.kind == kind }
    }

    /// Accepts results whose kind is in the given set.
    public static func kinds(_ kinds: Set<PrimitiveKind>) -> SelectionFilter {
        SelectionFilter { kinds.contains($0.kind) }
    }

    /// Faces only.
    public static let faces = kind(.face)

    /// Edges only.
    public static let edges = kind(.edge)

    /// Vertices only.
    public static let vertices = kind(.vertex)

    /// Accepts results on a specific pick layer.
    public static func layer(_ layer: PickLayer) -> SelectionFilter {
        SelectionFilter { $0.pickLayer == layer }
    }

    /// Accepts results whose body ID is in the allow-list.
    public static func bodyIDs(_ ids: Set<String>) -> SelectionFilter {
        SelectionFilter { ids.contains($0.bodyID) }
    }

    /// Rejects results whose body ID is in the deny-list.
    public static func excludingBodyIDs(_ ids: Set<String>) -> SelectionFilter {
        SelectionFilter { !ids.contains($0.bodyID) }
    }

    /// Accepts results whose draw-order body index is in the given set.
    public static func bodyIndices(_ indices: Set<Int>) -> SelectionFilter {
        SelectionFilter { indices.contains($0.bodyIndex) }
    }
}

// MARK: - Composition

extension SelectionFilter {

    /// Logical AND of this filter and another.
    public func and(_ other: SelectionFilter) -> SelectionFilter {
        SelectionFilter { self.matches($0) && other.matches($0) }
    }

    /// Logical OR of this filter and another.
    public func or(_ other: SelectionFilter) -> SelectionFilter {
        SelectionFilter { self.matches($0) || other.matches($0) }
    }

    /// Logical negation.
    public var negated: SelectionFilter {
        SelectionFilter { !self.matches($0) }
    }

    /// AND-combines a chain of filters. An empty chain accepts everything.
    public static func all(of filters: [SelectionFilter]) -> SelectionFilter {
        SelectionFilter { result in filters.allSatisfy { $0.matches(result) } }
    }

    /// OR-combines a chain of filters. An empty chain rejects everything.
    public static func any(of filters: [SelectionFilter]) -> SelectionFilter {
        SelectionFilter { result in filters.contains { $0.matches(result) } }
    }
}
