import Foundation
import ActivityKit

/// ActivityAttributes for the "time until next event" Live Activity (port of the Android Live Update
/// countdown, §5.7). Lives in `ios/Shared` so both the app target and the widget extension compile it.
///
/// The dynamic `ContentState` carries only the event title and its end (start) instant; the countdown
/// itself is rendered by the system via `Text(timerInterval:)`, so no per-second push updates are needed.
public struct EventCountdownAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable, Sendable {
        /// Title of the upcoming event (mirrors `PlannedTask.title`).
        public var eventTitle: String
        /// Absolute instant the event begins; used as the end of the countdown interval.
        public var eventDate: Date

        public init(eventTitle: String, eventDate: Date) {
            self.eventTitle = eventTitle
            self.eventDate = eventDate
        }
    }

    /// Stable identifier (the originating `PlannedTask.id` string) so the activity can be matched/ended.
    public var taskId: String

    public init(taskId: String) {
        self.taskId = taskId
    }
}
