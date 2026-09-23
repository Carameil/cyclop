import AppKit
import Foundation
import Testing
@testable import Cyclop

/// Тесты на `Agenda` — раскладку встреч календаря по дням.
/// Панель сюда не входит, как и везде: см. CONTRIBUTING.md.
struct AgendaTests {
    private let calendar: Foundation.Calendar = {
        var calendar = Foundation.Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Belgrade")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func meeting(_ title: String, _ start: Date, eventIdentifier: String = "series") -> CalendarStore.Meeting {
        CalendarStore.Meeting(
            id: Agenda.meetingID(eventIdentifier: eventIdentifier, start: start, title: title),
            title: title,
            start: start,
            end: start.addingTimeInterval(3600),
            calendarColor: .systemBlue,
            link: nil,
            provider: nil
        )
    }

    // MARK: - Идентификатор

    /// У всех повторов одной встречи EventKit отдаёт один `eventIdentifier`.
    @Test func occurrencesOfARecurringEventGetDistinctIds() {
        let wednesday = Agenda.meetingID(eventIdentifier: "lunch", start: date(23, 14), title: "Lunch")
        let thursday = Agenda.meetingID(eventIdentifier: "lunch", start: date(24, 14), title: "Lunch")
        #expect(wednesday != thursday)
    }

    @Test func missingEventIdentifierFallsBackToTitle() {
        let first = Agenda.meetingID(eventIdentifier: nil, start: date(23, 14), title: "A")
        let second = Agenda.meetingID(eventIdentifier: nil, start: date(23, 14), title: "B")
        #expect(first != second)
    }

    // MARK: - Дни

    @Test func meetingsOnADayKeepOnlyThatDayInOrder() {
        let all = [
            meeting("Standup", date(23, 12)),
            meeting("Lunch", date(23, 14)),
            meeting("Standup", date(24, 12)),
            meeting("Lunch", date(24, 14)),
        ]
        let thursday = Agenda.meetings(all, on: date(24, 0), calendar: calendar)
        #expect(thursday.map(\.start) == [date(24, 12), date(24, 14)])
    }

    @Test func aMeetingBelongsToTheDayItStarts() {
        let late = meeting("Late", date(23, 23, 30))
        #expect(Agenda.meetings([late], on: date(23, 0), calendar: calendar).count == 1)
        #expect(Agenda.meetings([late], on: date(24, 0), calendar: calendar).isEmpty)
    }

    @Test func daysStartAtMidnightOfTodayAndCoverTheHorizon() {
        let days = Agenda.days(from: date(23, 13, 45), count: 7, calendar: calendar)
        #expect(days.count == 7)
        #expect(days.first == date(23, 0))
        #expect(days.last == date(29, 0))
    }
}
