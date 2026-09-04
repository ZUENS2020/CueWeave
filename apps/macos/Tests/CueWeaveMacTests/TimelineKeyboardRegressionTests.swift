import Testing
@testable import CueWeaveMac

struct TimelineKeyboardRegressionTests {
    @Test("Holding N toggles once and consumes repeats")
    func nextDoesNotOscillate() {
        var translator = TimelineHotkeyTranslator()
        var key = input(45, "n")
        #expect(translator.translate(key) == .toggleFollowSelection)
        key.isRepeat = true
        #expect(translator.translate(key) == .consume)
        key.isKeyUp = true
        #expect(translator.translate(key) == nil)
        #expect(translator.translate(input(45, "n")) == .toggleFollowSelection)
    }

    @Test("Chord releases survive modifiers; leaving the window clears the chord")
    func releasedChord() {
        var translator = TimelineHotkeyTranslator()
        #expect(translator.translate(input(18, "1")) == .consume)
        var release = input(18, "1")
        release.isKeyUp = true
        release.command = true
        #expect(translator.translate(release) == .consume)
        #expect(translator.translate(input(123, "")) == .seekPlayhead(-1))
        _ = translator.translate(input(20, "3"))
        #expect(translator.translate(input(124, "")) == .nudgeFinal(50))
        translator = TimelineHotkeyTranslator()
        #expect(translator.translate(input(124, "")) == .seekPlayhead(1))
    }

    @Test("Releasing one step key does not release another held step")
    func overlappingChords() {
        var chord = TimelineKeyChordState()
        _ = chord.handle(symbol: "1", isArrowLeft: false, isArrowRight: false, phase: .down)
        _ = chord.handle(symbol: "3", isArrowLeft: false, isArrowRight: false, phase: .down)
        _ = chord.handle(symbol: "3", isArrowLeft: false, isArrowRight: false, phase: .up)
        #expect(chord.heldStep == 1)
    }

    private func input(_ code: UInt16, _ characters: String) -> TimelineHotkeyInput {
        TimelineHotkeyInput(keyCode: code, characters: characters, command: false, shift: false,
                            option: false, control: false, isKeyUp: false, isRepeat: false)
    }
}
