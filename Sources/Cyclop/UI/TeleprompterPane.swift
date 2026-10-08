import SwiftUI

/// The script, scrolling under the camera.
///
/// Three states rather than three tabs. The tab opens onto the page: the whole
/// script at a size meant for glancing at during a call, which is what a list
/// of notes is mostly used for. ▶ turns it into the teleprompter proper — large
/// type creeping upward — and ↺ turns it back. Editing is a step aside from
/// either.
struct TeleprompterPane: View {
    @ObservedObject var prompter: TeleprompterStore
    /// Whether the panel holds the keyboard, so the editor can follow it.
    @Binding var wantsKeyboard: Bool

    @State private var editing = false
    /// Whether the large scrolling text is up instead of the page.
    @State private var prompting = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if editing || prompter.script.isEmpty {
                editor
            } else if prompting {
                reader
            } else {
                page
            }
            controls
        }
        .padding(.top, 2)
        .onChange(of: wantsKeyboard) { _, wants in
            focused = wants && editing
            // The keyboard going elsewhere means attention went with it — but
            // not on an empty script, where the editor is the only thing this
            // tab can show. Saying it is not being edited would be untrue, and
            // the first character typed would then hand the pane to the reader
            // in mid-word.
            if !wants, !prompter.script.isEmpty { editing = false }
        }
        // Arriving puts the script back at the top. A take starts at the
        // beginning, and mid-take nobody is switching tabs — so the only way
        // to arrive on a script left halfway is to have finished with it, and
        // the one thing that must not happen then is opening onto the blank
        // space past the last line with no way to tell why it is blank.
        .onAppear {
            prompter.reload()
            prompter.rewind()
            // An empty script has nothing to read, so the tab opens into the
            // editor — and an editor the keyboard never reaches is a field
            // that cannot be typed or pasted into at all (#53). The one button
            // that would hand it over is the ✎, and it is on the other branch
            // of these controls; the panel does not offer it on arrival either,
            // because reading a script is not typing (`Tab.needsKeyboard`).
            //
            // So this state asks the way the ✎ asks. Hovering onto an empty
            // teleprompter does take the keyboard from the window underneath,
            // and that is the trade `PanelState.select` already names: showing
            // a field one cannot type into is worse than briefly dimming the
            // caret below. It happens once — a script that exists is read, not
            // written, and this branch is never taken again.
            //
            // The focus itself is asked for a pass later, the way the notes do:
            // this fires while the pane is still being put on screen, and a
            // focus requested from a field that is not yet in a key window is
            // dropped rather than queued. Arriving through the rail happened
            // to survive that; arriving by reopening the panel on this tab did
            // not, and the editor came back with its placeholder, its caret
            // gone, and no way to click one into it.
            guard prompter.script.isEmpty else { return }
            editing = true
            wantsKeyboard = true
            DispatchQueue.main.async { focused = true }
        }
        .onDisappear { prompter.suspend() }
    }

    // MARK: - Page

    /// The script laid out like the editor, minus the caret: same box, same
    /// column, a size that fits a whole stand-up on screen. Scrolled by hand,
    /// because nothing here moves by itself.
    private var page: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(prompter.formatted)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(.white)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, EditorInset.horizontal + 5)
                .padding(.vertical, EditorInset.vertical)
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 14)
    }

    // MARK: - Reading

    /// The line being read sits in the middle of the window, not at the top:
    /// what is coming is as much of the job as what is here, and a reader with
    /// nothing below the current line has nowhere to look ahead to.
    private var reader: some View {
        GeometryReader { outer in
            ScrollView(.vertical, showsIndicators: false) {
                Text(prompter.formatted)
                    .font(.system(size: prompter.fontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .lineSpacing(prompter.fontSize * 0.34)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 26)
                    // Half a window of blank above and below, so the first line
                    // starts at the reading mark and the last one can reach it.
                    .padding(.top, outer.size.height / 2)
                    .padding(.bottom, outer.size.height / 2)
                    .background(
                        GeometryReader { inner in
                            Color.clear.onAppear {
                                prompter.contentHeight = inner.size.height
                                prompter.viewportHeight = outer.size.height
                            }
                            .onChange(of: inner.size.height) { _, height in
                                prompter.contentHeight = height
                            }
                        }
                    )
                    .offset(y: -prompter.offset)
            }
            .scrollDisabled(true)
            .overlay(alignment: .top) { fade(.top) }
            .overlay(alignment: .bottom) { fade(.bottom) }
            .onAppear { prompter.viewportHeight = outer.size.height }
            .onChange(of: outer.size.height) { _, height in prompter.viewportHeight = height }
            // Measured afresh every time it comes up: a height left over from
            // an earlier script would end the next take early.
            .onDisappear { prompter.contentHeight = 0 }
        }
    }

    /// Where the eye rests, and the only thing that says so.
    ///
    /// There was a tick in the margin here as well, marking the line to read.
    /// It went: the first person to see it asked what it was, which is the
    /// whole verdict on a mark whose entire job is being understood without
    /// explanation. The fade already does that job — the band in the middle is
    /// the only fully lit text on screen, so the eye coming back from the lens
    /// lands on it without being pointed at anything.
    ///
    /// Text does not end at an edge, it dissolves into one — a hard cut reads
    /// as the script being clipped rather than continuing.
    private func fade(_ edge: VerticalEdge) -> some View {
        LinearGradient(
            colors: [.black, .black.opacity(0)],
            startPoint: edge == .top ? .top : .bottom,
            endPoint: edge == .top ? .bottom : .top
        )
        .frame(height: 34)
        .allowsHitTesting(false)
    }

    // MARK: - Editing

    /// Room between the text and the rounded rectangle it sits in. The editor
    /// has none of its own: its first line goes flush against its top-left
    /// corner, five points of line fragment padding aside, and a script
    /// pressed into the corner of a box reads as a mistake before it reads as
    /// text. Seven plus those five puts the first character at 26 from the
    /// pane's edge — the same column the reader puts it in.
    private enum EditorInset {
        static let horizontal: CGFloat = 7
        static let vertical: CGFloat = 10
    }

    private var editor: some View {
        TextEditor(text: $prompter.script)
            .font(.system(size: 13, design: .rounded))
            .scrollContentBackground(.hidden)
            .foregroundStyle(.white)
            .focused($focused)
            // Inside the surface, so the box keeps its size and the text moves
            // in from its edges.
            .padding(.horizontal, EditorInset.horizontal)
            .padding(.vertical, EditorInset.vertical)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 14)
            .overlay(alignment: .topLeading) {
                if prompter.script.isEmpty {
                    // Offsets match where the editor actually puts its first
                    // line, not where the rounded rectangle starts: 14 is the
                    // padding around the box, then the inset above, then the
                    // text container's own 5 pt of line fragment padding.
                    // Getting this wrong parks the caret above and left of the
                    // placeholder it is supposed to stand in front of.
                    Text("Paste the script here")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Theme.tertiary)
                        .padding(.leading, 14 + EditorInset.horizontal + 5)
                        .padding(.top, EditorInset.vertical)
                        .allowsHitTesting(false)
                }
            }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 14) {
            if editing || prompter.script.isEmpty {
                Spacer()
                Button(prompter.script.isEmpty ? "Ready" : "Done") {
                    editing = false
                    wantsKeyboard = false
                }
                .buttonStyle(.plain)
                .pointerStyle(.default)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(prompter.script.isEmpty ? Theme.tertiary : .white)
                .disabled(prompter.script.isEmpty)
            } else {
                if prompting {
                    Button {
                        prompter.rewind()
                        prompting = false
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(NotchButtonStyle(size: 26))
                }

                Button {
                    prompting = true
                    prompter.toggle()
                } label: {
                    Image(systemName: prompter.isRunning ? "pause.fill" : "play.fill")
                }
                .buttonStyle(NotchButtonStyle(size: 32, prominent: true))

                speedControl

                Spacer()

                if prompting { sizeControl }

                Button {
                    prompter.pause()
                    prompting = false
                    editing = true
                    wantsKeyboard = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(NotchButtonStyle(size: 26))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .frame(height: 44)
    }

    /// A slider rather than presets: the right pace depends on the script and
    /// on the person, and it is found by moving it while reading, not chosen
    /// from a list beforehand.
    private var speedControl: some View {
        HStack(spacing: 7) {
            Slider(value: $prompter.speed, in: 0.3...3.0)
                .controlSize(.mini)
                .tint(.white.opacity(0.7))
                .frame(width: 96)
            Text(String(format: "%.1f×", prompter.speed))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.secondary)
                .frame(width: 30, alignment: .leading)
        }
    }

    private var sizeControl: some View {
        HStack(spacing: 4) {
            Button { prompter.fontSize = max(18, prompter.fontSize - 2) } label: {
                Image(systemName: "textformat.size.smaller")
            }
            .buttonStyle(NotchButtonStyle(size: 26))
            Button { prompter.fontSize = min(64, prompter.fontSize + 2) } label: {
                Image(systemName: "textformat.size.larger")
            }
            .buttonStyle(NotchButtonStyle(size: 26))
        }
    }
}
