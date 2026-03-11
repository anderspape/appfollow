import SwiftUI
import AppKit

struct StatusBarEditableSubtaskRow<DurationPickerContent: View, VisualPickerContent: View>: View {
    @Binding var task: FocusTask
    let showsDuration: Bool
    let theme: StatusBarTimerTheme
    let settingsPillBackground: Color

    @Binding var hoveredTaskID: UUID?
    var focusedSubtaskID: FocusState<UUID?>.Binding
    @Binding var editingTaskDurationID: UUID?

    let onRemove: (UUID) -> Void
    let onTitleChange: (UUID, String) -> Void
    let onVisualTap: (UUID) -> Void
    let durationPopoverBinding: (UUID) -> Binding<Bool>
    let durationPickerContent: (Binding<FocusTask>) -> DurationPickerContent
    let visualPopoverBinding: (UUID) -> Binding<Bool>
    let visualPickerContent: (Binding<FocusTask>) -> VisualPickerContent

    var body: some View {
        let taskID = task.id
        let isHovered = hoveredTaskID == taskID
        let isTitleFocused = focusedSubtaskID.wrappedValue == taskID
        let showTitleFieldHighlight = isHovered || isTitleFocused
        let titleBinding = Binding<String>(
            get: { task.title },
            set: { newTitle in
                task.title = newTitle
                onTitleChange(taskID, newTitle)
            }
        )

        return HStack(spacing: 10) {
            Button {
                onVisualTap(taskID)
            } label: {
                Text(task.emoji)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 27, height: 27)
                    .background(
                        Circle()
                            .fill(Color(hex: task.accentHex) ?? Color(red: 0.93, green: 0.92, blue: 0.99))
                    )
            }
            .buttonStyle(.plain)
            .statusBarHoverEffect()
            .popover(
                isPresented: visualPopoverBinding(taskID),
                arrowEdge: .top
            ) {
                visualPickerContent($task)
            }

            TextField("Sub-task", text: titleBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.primaryTextColor)
                .focused(focusedSubtaskID, equals: taskID)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            theme.colorScheme == .dark
                                ? Color.white.opacity(showTitleFieldHighlight ? 0.1 : 0.0001)
                                : Color.black.opacity(showTitleFieldHighlight ? 0.065 : 0.0001)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(
                                    Color.white.opacity(showTitleFieldHighlight ? (theme.colorScheme == .dark ? 0.14 : 0.28) : 0),
                                    lineWidth: 0.6
                                )
                        )
                )
                .animation(.easeInOut(duration: 0.2), value: showTitleFieldHighlight)

            Spacer(minLength: 8)

            if showsDuration {
                Button {
                    editingTaskDurationID = taskID
                } label: {
                    HStack(spacing: 6) {
                        Text(StatusBarTimerDraftHelpers.formattedDuration(task.durationMinutes))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.primaryTextColor)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(settingsPillBackground, in: Capsule())
                }
                .buttonStyle(.plain)
                .statusBarHoverEffect()
                .popover(
                    isPresented: durationPopoverBinding(taskID),
                    arrowEdge: .top
                ) {
                    durationPickerContent($task)
                }
            }

            Button {
                onRemove(taskID)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.secondaryTextColor)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .statusBarHoverEffect()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: theme.innerCardCornerRadius, style: .continuous)
                .fill(theme.taskCardFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.innerCardCornerRadius, style: .continuous)
                        .stroke(isHovered ? theme.taskCardHoverStrokeColor : theme.taskCardStrokeColor, lineWidth: isHovered ? 1.1 : 0.8)
                )
        )
        .animation(.easeInOut(duration: 0.22), value: isHovered)
        .onHover { isHovering in
            if isHovering {
                NSCursor.openHand.set()
            } else {
                NSCursor.arrow.set()
            }

            if isHovering {
                hoveredTaskID = taskID
            } else if hoveredTaskID == taskID {
                hoveredTaskID = nil
            }
        }
        .onDisappear {
            if hoveredTaskID == taskID {
                hoveredTaskID = nil
            }
            if focusedSubtaskID.wrappedValue == taskID {
                focusedSubtaskID.wrappedValue = nil
            }
            if editingTaskDurationID == taskID {
                editingTaskDurationID = nil
            }
        }
    }
}
