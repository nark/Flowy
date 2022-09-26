// Copyright AudioKit. All Rights Reserved. Revision History at http://github.com/AudioKit/Flow/

import SwiftUI

extension NodeEditor {
    /// State for all gestures.
    enum DragInfo {
        case wire(output: OutputID, offset: CGSize = .zero, hideWire: Wire? = nil)
        case node(index: NodeIndex, offset: CGSize = .zero)
        case selection(rect: CGRect = .zero)
        case none
    }

    /// Adds a new wire to the patch, ensuring that multiple wires aren't connected to an input.
    func connect(_ output: OutputID, to input: InputID) {
        let wire = Wire(from: output, to: input)

        // Remove any other wires connected to the input.
        patch.wires = patch.wires.filter { w in
            let result = w.input != wire.input
            if !result {
                wireRemoved(w)
            }
            return result
        }
        patch.wires.insert(wire)
        wireAdded(wire)
    }

    func attachedWire(inputID: InputID) -> Wire? {
        patch.wires.first(where: { $0.input == inputID })
    }

    func toLocal(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x / CGFloat(zoom), y: p.y / CGFloat(zoom)) - pan
    }

    func toLocal(_ sz: CGSize) -> CGSize {
        CGSize(width: sz.width / CGFloat(zoom), height: sz.height / CGFloat(zoom))
    }

    func update(drag: DragGesture.Value, dragInfo: inout NodeEditor.DragInfo, _ _: inout Transaction) {

        let startLocation = toLocal(drag.startLocation)
        let location = toLocal(drag.location)
        let translation = toLocal(drag.translation)

        switch patch.hitTest(point: startLocation, layout: layout) {
        case .none:
            dragInfo = .selection(rect: CGRect(a: startLocation,
                                               b: location))
        case let .node(nodeIndex):
            dragInfo = .node(index: nodeIndex, offset: translation)
        case let .output(nodeIndex, portIndex):
            dragInfo = DragInfo.wire(output: OutputID(nodeIndex, portIndex), offset: translation)
        case let .input(nodeIndex, portIndex):
            let node = patch.nodes[nodeIndex]
            // Is a wire attached to the input?
            if let attachedWire = attachedWire(inputID: InputID(nodeIndex, portIndex)) {
                let offset = node.inputRect(input: portIndex, layout: layout).center
                    - patch.nodes[attachedWire.output.nodeIndex].outputRect(
                        output: attachedWire.output.portIndex,
                        layout: layout
                    ).center
                    + translation
                dragInfo = .wire(output: attachedWire.output,
                                 offset: offset,
                                 hideWire: attachedWire)
            }
        }

    }

    func end(drag: GestureStateGesture<DragGesture, NodeEditor.DragInfo>.Value) {
        let startLocation = toLocal(drag.startLocation)
        let location = toLocal(drag.location)
        let translation = toLocal(drag.translation)

        let hitResult = patch.hitTest(point: startLocation, layout: layout)

        // Note that this threshold should be in screen coordinates.
        if drag.distance > 5 {
            switch hitResult {
            case .none:
                let selectionRect = CGRect(a: startLocation, b: location)
                selection = self.patch.selected(
                    in: selectionRect,
                    layout: layout
                )
            case let .node(nodeIndex):
                patch.moveNode(
                    nodeIndex: nodeIndex,
                    offset: translation,
                    nodeMoved: self.nodeMoved
                )
                if selection.contains(nodeIndex) {
                    for idx in selection where idx != nodeIndex {
                        patch.moveNode(
                            nodeIndex: idx,
                            offset: translation,
                            nodeMoved: self.nodeMoved
                        )
                    }
                }
            case let .output(nodeIndex, portIndex):
                if let input = findInput(point: location) {
                    connect(OutputID(nodeIndex, portIndex), to: input)
                }
            case let .input(nodeIndex, portIndex):
                // Is a wire attached to the input?
                if let attachedWire = attachedWire(inputID: InputID(nodeIndex, portIndex)) {
                    patch.wires.remove(attachedWire)
                    wireRemoved(attachedWire)
                    if let input = findInput(point: location) {
                        connect(attachedWire.output, to: input)
                    }
                }
            }
        } else {
            // If we haven't moved far, then this is effectively a tap.
            switch hitResult {
            case .none:
                selection = Set<NodeIndex>()
            case let .node(nodeIndex):
                selection = Set<NodeIndex>([nodeIndex])
            default: break
            }
        }
    }

    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($dragInfo, body: update)
            .onEnded(end)
    }
}

extension DragGesture.Value {
    @inlinable @inline(__always)
    var distance: CGFloat {
        startLocation.distance(to: location)
    }
}
