import SwiftUI

struct SubtaskDropDelegate: DropDelegate {
    let targetTaskID: UUID
    @Binding var tasks: [FocusTask]
    @Binding var draggedTaskID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedTaskID,
              draggedTaskID != targetTaskID,
              let fromIndex = tasks.firstIndex(where: { $0.id == draggedTaskID }),
              let toIndex = tasks.firstIndex(where: { $0.id == targetTaskID })
        else {
            return
        }

        withAnimation(.easeInOut(duration: 0.16)) {
            tasks.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedTaskID = nil
        return true
    }
}
