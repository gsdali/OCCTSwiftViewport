// SelectionMode.swift
// OCCTSwiftMetalDemo
//
// Selection granularity for the demo viewport.

/// Selection granularity for picking.
enum SelectionMode: String, CaseIterable, Sendable {
    case body
    case face
    case edge
    case vertex
}
