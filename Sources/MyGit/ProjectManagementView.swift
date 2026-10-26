import SwiftUI

struct ProjectManagementView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var editingID: UUID?
    @State private var draftName = ""
    @State private var draggingID: UUID?
    @State private var dragOffset: CGFloat = 0
    @FocusState private var focusedID: UUID?

    private var invalidName: Bool {
        editingID != nil && draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("管理工程").appFont(size: 20, weight: .semibold)
            Text("拖动工程调整顺序，双击名称重命名。修改自动保存。")
                .appFont(size: 12).foregroundStyle(WorkbenchStyle.muted)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.projects) { project in
                        projectRow(project)
                    }
                }
                .padding(8)
                .coordinateSpace(name: "projectList")
            }
            .background(WorkbenchStyle.background, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(WorkbenchStyle.border))
            .overlay {
                if model.projects.isEmpty {
                    Text("还没有工程").appFont(size: 12).foregroundStyle(WorkbenchStyle.muted)
                }
            }

            HStack {
                if editingID != nil {
                    Button("取消") { cancelEditing() }
                        .buttonStyle(WorkbenchButtonStyle())
                        .keyboardShortcut(.cancelAction)
                }
                if invalidName {
                    Text("工程名称不能为空").appFont(size: 12).foregroundStyle(.red)
                }
                Spacer()
                Button("完成") {
                    if finishEditing() { dismiss() }
                }
                .buttonStyle(WorkbenchButtonStyle(emphasized: true))
                .keyboardShortcut(.defaultAction)
                .disabled(invalidName)
            }
        }
        .padding(24)
        .frame(width: 520, height: 400)
        .background(WorkbenchStyle.sidebar)
        .preferredColorScheme(.dark)
        .onChange(of: focusedID) { old, new in
            if let old, editingID == old, new != old, !finishEditing() { focusedID = editingID }
        }
        .onExitCommand {
            if editingID != nil { cancelEditing() }
            else { dismiss() }
        }
    }

    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(WorkbenchStyle.muted)
                .frame(width: 24, height: 36)
                .contentShape(Rectangle())
                .gesture(DragGesture(coordinateSpace: .named("projectList"))
                    .onChanged { value in
                        guard finishEditing() else { return }
                        draggingID = project.id
                        dragOffset = value.translation.height
                    }
                    .onEnded { value in
                        if let source = model.projects.firstIndex(where: { $0.id == project.id }), draggingID == project.id {
                            let target = min(model.projects.count - 1, max(0, source + Int((value.translation.height / 44).rounded())))
                            model.moveProjects(from: IndexSet(integer: source), to: target > source ? target + 1 : target)
                        }
                        draggingID = nil
                        dragOffset = 0
                    })
                .help("拖动调整顺序")
                .accessibilityHidden(true)
            if editingID == project.id {
                TextField("工程名称", text: $draftName)
                    .textFieldStyle(.plain)
                    .focused($focusedID, equals: project.id)
                    .onSubmit { _ = finishEditing() }
                    .onExitCommand { cancelEditing() }
                    .modifier(WorkbenchControlSurface(isFocused: focusedID == project.id))
                    .accessibilityLabel(Text("工程名称"))
            } else {
                Text(project.name)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { beginEditing(project) }
                    .help(project.name)
            }
            Text(AppLocalization.text("%ld repositories", project.repositories.count))
                .foregroundStyle(WorkbenchStyle.muted)
                .fixedSize()
            Button { beginEditing(project) } label: {
                Image(systemName: "pencil").frame(width: 24, height: 24)
            }
            .buttonStyle(WorkbenchHoverButtonStyle())
            .help("重命名工程")
            .accessibilityLabel(Text("重命名工程"))
        }
        .appFont(size: 12)
        .frame(minHeight: 36)
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(draggingID == project.id ? WorkbenchStyle.surface : Color.clear,
                    in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .offset(y: draggingID == project.id ? dragOffset : 0)
        .zIndex(draggingID == project.id ? 1 : 0)
        .workbenchHoverFeedback(cornerRadius: 4)
        .contextMenu {
            Button("重命名工程") { beginEditing(project) }
            Button("上移") { move(project, down: false) }
                .disabled(model.projects.first?.id == project.id)
            Button("下移") { move(project, down: true) }
                .disabled(model.projects.last?.id == project.id)
        }
    }

    private func beginEditing(_ project: Project) {
        guard editingID != project.id, finishEditing() else { return }
        draftName = project.name
        editingID = project.id
        focusedID = project.id
    }

    @discardableResult
    private func finishEditing() -> Bool {
        guard let id = editingID else { return true }
        guard !invalidName else { return false }
        model.renameProject(id, name: draftName)
        editingID = nil
        focusedID = nil
        return true
    }

    private func cancelEditing() {
        editingID = nil
        focusedID = nil
    }

    private func move(_ project: Project, down: Bool) {
        guard finishEditing(), let index = model.projects.firstIndex(where: { $0.id == project.id }) else { return }
        model.moveProjects(from: IndexSet(integer: index), to: down ? index + 2 : index - 1)
    }
}
