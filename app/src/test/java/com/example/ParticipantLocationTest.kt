package com.example

import com.example.core.data.Person
import com.example.core.data.SavedZone
import com.example.core.data.localLocationLabel
import com.example.feature.planner.buildMeetingParticipants
import com.example.feature.planner.buildParticipantLocationGroups
import com.example.feature.planner.buildSelectedParticipantLabels
import com.example.feature.planner.contactsForZone
import com.example.feature.planner.plannerParticipantPool
import com.example.feature.planner.unassignedContactGroups
import com.example.feature.planner.visiblePlannerGroups
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ParticipantLocationTest {

  @Test
  fun sameTimeZoneCitiesMergeIntoOneGroup() {
    val denver = SavedZone(id = "America/Denver", displayName = "Denver", isFavorite = true)
    val sreeja = Person(
      name = "Sreeja",
      zoneId = "America/Denver",
      locationName = "El Paso",
      isFavorite = true,
    )

    val groups = buildParticipantLocationGroups(listOf(denver), listOf(sreeja))

    assertEquals(1, groups.size)
    assertEquals("Denver, El Paso", groups.single().displayName)
    assertEquals(listOf(sreeja), groups.single().people)
  }

  @Test
  fun slotLabelsUseOneTagPerTimeZone() {
    val denver = SavedZone(id = "America/Denver", displayName = "Denver", isFavorite = true)
    val sreeja = Person(
      id = 1,
      name = "Sreeja",
      zoneId = "America/Denver",
      locationName = "El Paso",
      isFavorite = true,
    )
    val groups = buildParticipantLocationGroups(listOf(denver), listOf(sreeja))

    val labels = buildSelectedParticipantLabels(
      localZoneId = "America/Chicago",
      localLocationName = "Chicago",
      groups = groups,
      selectedZones = mapOf(denver.id to true),
      selectedPeople = mapOf(sreeja.id to true),
    )

    assertEquals(2, labels.size)
    assertEquals("Denver, El Paso", labels[1].locationLabel)
    assertEquals("Sreeja · Denver, El Paso", labels[1].displayWho())
  }

  @Test
  fun orphanSameTimeZoneRoutesToPinnedRow() {
    val denver = SavedZone(id = "America/Denver", displayName = "Denver", isFavorite = true)
    val sreeja = Person(
      name = "Sreeja",
      zoneId = "America/Denver",
      locationName = "El Paso",
      isFavorite = true,
    )

    assertTrue(unassignedContactGroups(listOf(sreeja), listOf(denver)).isEmpty())
    assertEquals(listOf(sreeja), contactsForZone(denver, listOf(sreeja), listOf(denver)))
  }

  @Test
  fun orphanShowsWhenNoPinnedTimeZone() {
    val sreeja = Person(
      name = "Sreeja",
      zoneId = "America/Denver",
      locationName = "El Paso",
      isFavorite = true,
    )

    val orphans = unassignedContactGroups(listOf(sreeja), emptyList())
    assertEquals(1, orphans.size)
    assertEquals("El Paso", orphans.first().displayName)
  }

  @Test
  fun plannerPoolSkipsHomeAndLocalZone() {
    val pool = plannerParticipantPool(
      savedZones = listOf(
        SavedZone(id = "America/Denver", displayName = "Denver", isFavorite = true),
        SavedZone(id = "America/Chicago", displayName = "Chicago", isHome = true, isFavorite = true),
      ),
      people = listOf(
        Person(name = "Sreeja", zoneId = "America/Denver", locationName = "El Paso", isFavorite = true),
      ),
      localZoneId = "America/Chicago",
    )

    assertEquals(1, pool.zones.size)
    assertEquals("Denver", pool.zones.single().displayName)
  }

  @Test
  fun visiblePlannerGroupsHideLocalZoneOnlyDuplicate() {
    val denver = SavedZone(id = "America/Chicago", displayName = "Chicago", isFavorite = true)
    val groups = buildParticipantLocationGroups(listOf(denver), emptyList())

    assertTrue(visiblePlannerGroups(groups, "America/Chicago").isEmpty())
  }

  @Test
  fun localLabelsSkipRedundantZoneOnlyRow() {
    val chicago = SavedZone(id = "America/Chicago", displayName = "Chicago", isFavorite = true)
    val groups = buildParticipantLocationGroups(listOf(chicago), emptyList())

    val labels = buildSelectedParticipantLabels(
      localZoneId = "America/Chicago",
      localLocationName = "Chicago",
      groups = visiblePlannerGroups(groups, "America/Chicago"),
      selectedZones = mapOf(chicago.id to true),
      selectedPeople = emptyMap(),
    )

    assertEquals(1, labels.size)
    assertEquals("You · Chicago", labels.single().locationLabel)
  }

  @Test
  fun meetingParticipantsMergeSameTimeZoneOnce() {
    val denver = SavedZone(id = "America/Denver", displayName = "Denver", isFavorite = true)
    val sreeja = Person(
      id = 1,
      name = "Sreeja",
      zoneId = "America/Denver",
      locationName = "El Paso",
      isFavorite = true,
      workStartHour = 10,
      workEndHour = 18,
    )
    val groups = buildParticipantLocationGroups(listOf(denver), listOf(sreeja))

    val participants = buildMeetingParticipants(
      localZoneId = "America/Chicago",
      groups = groups,
      selectedZones = mapOf(denver.id to true),
      selectedPeople = mapOf(sreeja.id to true),
    )

    assertEquals(2, participants.size)
    val mountain = participants.single { it.zoneId == "America/Denver" }
    assertEquals(10, mountain.workStartHour)
    assertEquals(18, mountain.workEndHour)
  }

  @Test
  fun nonFavoriteContactNotOnZoneRow() {
    val denver = SavedZone(id = "America/Denver", displayName = "Denver", isFavorite = true)
    val sreeja = Person(
      name = "Sreeja",
      zoneId = "America/Denver",
      locationName = "El Paso",
      isFavorite = false,
    )

    assertTrue(contactsForZone(denver, listOf(sreeja), listOf(denver)).isEmpty())
  }

  @Test
  fun unfavoritedPinnedZoneDoesNotAbsorbOrphan() {
    val denver = SavedZone(id = "America/Denver", displayName = "Denver", isFavorite = false)
    val sreeja = Person(
      name = "Sreeja",
      zoneId = "America/Denver",
      locationName = "El Paso",
      isFavorite = true,
    )

    assertTrue(contactsForZone(denver, listOf(sreeja), listOf(denver)).isEmpty())
    assertEquals(1, unassignedContactGroups(listOf(sreeja), listOf(denver)).size)
  }

  @Test
  fun contactOnlyGroupParticipatesWhenPersonSelected() {
    val sreeja = Person(
      id = 2,
      name = "Sreeja",
      zoneId = "America/Denver",
      locationName = "El Paso",
      isFavorite = true,
      workStartHour = 8,
      workEndHour = 16,
    )
    val groups = buildParticipantLocationGroups(emptyList(), listOf(sreeja))

    val participants = buildMeetingParticipants(
      localZoneId = "America/Chicago",
      groups = groups,
      selectedZones = emptyMap(),
      selectedPeople = mapOf(sreeja.id to true),
    )

    assertEquals(2, participants.size)
    val mountain = participants.single { it.zoneId == "America/Denver" }
    assertEquals(8, mountain.workStartHour)
    assertEquals(16, mountain.workEndHour)
  }

  @Test
  fun localLocationLabelUsesHomeCityNotTimeZone() {
    val savedZones = listOf(
      SavedZone(
        id = "America/Chicago",
        displayName = "Denton",
        isHome = true,
        anchorRole = "residence",
      ),
    )

    assertEquals("Denton", savedZones.localLocationLabel("America/Chicago"))
  }

  @Test
  fun localLabelsUseHomeCityNameOnYouChip() {
    val home = SavedZone(
      id = "America/Chicago",
      displayName = "Denton",
      isHome = true,
      anchorRole = "residence",
      isFavorite = true,
    )
    val denver = SavedZone(id = "America/Denver", displayName = "Denver", isFavorite = true)
    val groups = buildParticipantLocationGroups(listOf(denver), emptyList())

    val labels = buildSelectedParticipantLabels(
      localZoneId = "America/Chicago",
      localLocationName = listOf(home).localLocationLabel("America/Chicago"),
      groups = groups,
      selectedZones = mapOf(denver.id to true),
      selectedPeople = emptyMap(),
    )

    assertEquals("You · Denton", labels.first().locationLabel)
    assertEquals("Denver", labels[1].locationLabel)
  }

  @Test
  fun differentTimeZonesStaySeparate() {
    val denver = SavedZone(id = "America/Denver", displayName = "Denver", isFavorite = true)
    val london = SavedZone(id = "Europe/London", displayName = "London", isFavorite = true)

    val groups = buildParticipantLocationGroups(listOf(denver, london), emptyList())

    assertEquals(2, groups.size)
    assertEquals(setOf("Denver", "London"), groups.map { it.displayName }.toSet())
  }
}
