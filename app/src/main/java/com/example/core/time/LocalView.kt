package com.example.core.time

/**
 * How a wall-clock hour reads for a participant, used to annotate meeting slots (§5.8, §13).
 * Carried as an explicit enum (never color alone, §15) so each state pairs with an icon + label.
 */
enum class LocalView {
    ASLEEP,
    OUTSIDE_HOURS,
    WORKING,
    AWAKE,
}
