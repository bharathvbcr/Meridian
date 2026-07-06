package com.example.core.ai

import com.example.core.data.Person
import com.example.core.data.PlannedTask
import com.example.core.data.SavedZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Drift guard for the application semantic layer under /semantic. A hand-written semantic layer is
 * only trustworthy if it cannot silently diverge from the real schema, so this test binds
 * `semantic/meridian.yml` to the actual Room entity columns and `semantic/functions.yml` to the
 * Gemini function declarations. It reflects on the entities (Room annotations are compile-time, so
 * column == Kotlin property name here) — no database or Android runtime needed.
 */
class SemanticModelConsistencyTest {

    // Columns that are intentionally NOT part of the semantic model (internal plumbing).
    private val unmodeledByDesign = setOf("externalId") // import-dedup key on planned_tasks

    private val entities = listOf(SavedZone::class.java, Person::class.java, PlannedTask::class.java)

    private val realColumns: Set<String> = entities
        .flatMap { it.declaredFields.asList() }
        .filterNot { it.isSynthetic || it.name == "Companion" || it.name.contains('$') }
        .map { it.name }
        .toSet()

    // Column references in the model: bare `sql: <col>` and `{cube}.<col>` expressions.
    private val bareSql = Regex("""(?m)^\s*sql:\s*([A-Za-z_][A-Za-z0-9_]*)\s*$""")
    private val cubeRef = Regex("""\{[A-Za-z_]+}\.([A-Za-z_][A-Za-z0-9_]*)""")

    @Test
    fun model_referencesOnlyRealColumns() {
        val yaml = readSemantic("meridian.yml")
        val modeled = (bareSql.findAll(yaml) + cubeRef.findAll(yaml)).map { it.groupValues[1] }.toSet()
        val phantom = modeled - realColumns
        assertTrue(
            "meridian.yml references columns that do not exist on any Room entity: $phantom\n" +
                "(real columns: ${realColumns.sorted()})",
            phantom.isEmpty(),
        )
    }

    @Test
    fun everyRealColumnIsModeledOrExplicitlyExcluded() {
        val yaml = readSemantic("meridian.yml")
        val modeled = (bareSql.findAll(yaml) + cubeRef.findAll(yaml)).map { it.groupValues[1] }.toSet()
        val missing = realColumns - modeled - unmodeledByDesign
        assertTrue(
            "Room columns exist but are neither modeled in meridian.yml nor allow-listed as internal: " +
                "$missing\nAdd a dimension/measure for each, or add it to unmodeledByDesign with a reason.",
            missing.isEmpty(),
        )
    }

    @Test
    fun functions_matchGeminiFunctionDeclarations() {
        val functionsYaml = readSemantic("functions.yml")
        val toolsSource = repoFile("app/src/main/java/com/example/core/ai/MeridianAiTools.kt").readText()
        for (fn in listOf("get_current_time", "convert_time", "find_meeting_time")) {
            assertTrue("functions.yml is missing verb '$fn'", functionsYaml.contains("name: $fn"))
            assertTrue(
                "functions.yml declares '$fn' but MeridianAiTools has no such FunctionDeclaration",
                toolsSource.contains("\"$fn\""),
            )
        }
    }

    @Test
    fun routingContract_matchesCachePolicy() {
        val routing = readSemantic("functions.yml")

        // Intents the spec says are ALWAYS bypassed, e.g. cache_bypass_intents: ["CURRENT_TIME", "SCHEDULE"]
        val alwaysBypass = Regex("""cache_bypass_intents:\s*\[([^\]]*)]""")
            .find(routing)?.groupValues?.get(1).orEmpty()
            .let { Regex("\"([A-Z_]+)\"").findAll(it).map { m -> m.groupValues[1] }.toSet() }

        // Intents bypassed only when the prompt contains a word, e.g. { CONVERT: ["now"] }
        val conditional: Map<String, List<String>> =
            Regex("""cache_bypass_when_prompt_contains:\s*\{([^}]*)}""")
                .find(routing)?.groupValues?.get(1).orEmpty()
                .let { block ->
                    Regex("""([A-Z_]+):\s*\[([^\]]*)]""").findAll(block).associate { m ->
                        m.groupValues[1] to Regex("\"([a-z]+)\"")
                            .findAll(m.groupValues[2]).map { it.groupValues[1] }.toList()
                    }
                }

        assertTrue("functions.yml routing block did not parse", alwaysBypass.isNotEmpty())

        // Drive the real runtime policy for every intent and assert it agrees with the spec.
        for (intent in AiQueryIntent.values()) {
            val name = intent.name
            when {
                name in alwaysBypass ->
                    assertTrue(
                        "$name is declared cache_bypass_intents but SemanticCachePolicy did not bypass it",
                        SemanticCachePolicy.shouldBypass(intent, "any prompt here"),
                    )

                name in conditional -> {
                    val trigger = conditional.getValue(name).first()
                    assertTrue(
                        "$name with '$trigger' should bypass per spec, but policy did not",
                        SemanticCachePolicy.shouldBypass(intent, "convert $trigger to London"),
                    )
                    assertFalse(
                        "$name without a trigger word must NOT bypass, but policy did",
                        SemanticCachePolicy.shouldBypass(intent, "convert 3 pm to London"),
                    )
                }

                else ->
                    assertFalse(
                        "$name is not declared bypass-able, but SemanticCachePolicy bypassed a neutral prompt",
                        SemanticCachePolicy.shouldBypass(intent, "hello there"),
                    )
            }
        }

        // Sanity: the spec's set is exactly what the code enforces unconditionally.
        val codeAlwaysBypass = AiQueryIntent.values()
            .filter { SemanticCachePolicy.shouldBypass(it, "neutral prompt with no keywords") }
            .map { it.name }
            .toSet()
        assertEquals(
            "Spec's cache_bypass_intents and code's unconditional bypass set have diverged",
            alwaysBypass, codeAlwaysBypass,
        )
    }

    // --- file location -------------------------------------------------------------------------

    private fun readSemantic(name: String): String = repoFile("semantic/$name").readText()

    private fun repoFile(relative: String): File {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null) {
            val candidate = File(dir, relative)
            if (File(dir, "semantic/meridian.yml").exists()) return candidate
            dir = dir.parentFile
        }
        error("Could not locate repo root (semantic/meridian.yml) from ${System.getProperty("user.dir")}")
    }
}
