import Testing
@testable import FocusTimer

struct SubtaskBreakdownTaskParserTests {
    @Test
    func parserClampsUnreachableLowTotal() {
        let tasks = SubtaskBreakdownTaskParser.parseTasks(
            from: """
            {"tasks":[
                {"title":"A","emoji":"🧠","durationMinutes":20,"accentHex":"#EBFCF2"},
                {"title":"B","emoji":"✅","durationMinutes":20,"accentHex":"#FCEDEB"},
                {"title":"C","emoji":"📝","durationMinutes":20,"accentHex":"#FAEFE0"}
            ]}
            """,
            totalMinutes: 1,
            defaultPalette: ["#EBFCF2", "#FCEDEB", "#FAEFE0"]
        )

        #expect(tasks != nil)
        #expect(tasks?.count == 3)
        let total = tasks?.reduce(0, { $0 + $1.durationMinutes }) ?? -1
        #expect(total == 3)
        #expect(tasks?.allSatisfy({ $0.durationMinutes >= 1 && $0.durationMinutes <= 120 }) == true)
    }

    @Test
    func parserClampsUnreachableHighTotal() {
        let tasks = SubtaskBreakdownTaskParser.parseTasks(
            from: """
            {"tasks":[
                {"title":"A","emoji":"🧠","durationMinutes":20,"accentHex":"#EBFCF2"},
                {"title":"B","emoji":"✅","durationMinutes":20,"accentHex":"#FCEDEB"},
                {"title":"C","emoji":"📝","durationMinutes":20,"accentHex":"#FAEFE0"}
            ]}
            """,
            totalMinutes: 500,
            defaultPalette: ["#EBFCF2", "#FCEDEB", "#FAEFE0"]
        )

        #expect(tasks != nil)
        #expect(tasks?.count == 3)
        let total = tasks?.reduce(0, { $0 + $1.durationMinutes }) ?? -1
        #expect(total == 360)
        #expect(tasks?.allSatisfy({ $0.durationMinutes >= 1 && $0.durationMinutes <= 120 }) == true)
    }
}
