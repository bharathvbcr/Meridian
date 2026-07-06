package com.example.core.ai

import org.junit.Assert.assertTrue
import org.junit.Test
import org.yaml.snakeyaml.Yaml
import java.io.File

/**
 * Structural integrity of the semantic layer's INTERNAL references. The regex-based
 * [SemanticModelConsistencyTest] binds the model to the Kotlin code (columns, verbs, routing);
 * this one parses the YAML and checks the model is self-consistent — every view `include` names a
 * real dimension/measure on the cube reached by its `join_path`, and every function `resolves:`
 * target points at a real cube.dimension. A typo like `display_naem` passes the column guard but
 * would break at query time; this catches it at build time.
 */
class SemanticModelStructureTest {

    private val model = load("meridian.yml")
    private val functions = load("functions.yml")

    private val cubes: List<Map<String, Any?>> = model["cubes"].asListOfMaps()
    private val cubeNames: Set<String> = cubes.map { it["name"] as String }.toSet()

    // cube -> every queryable member (dimension names + measure names)
    private val members: Map<String, Set<String>> = cubes.associate { c ->
        val dims = c["dimensions"].asListOfMaps().map { it["name"] as String }
        val meas = c["measures"].asListOfMaps().map { it["name"] as String }
        (c["name"] as String) to (dims + meas).toSet()
    }

    // cube -> (joinName -> target cube). In Cube, a join's `name` IS the joined cube's name.
    private val joins: Map<String, Map<String, String>> = cubes.associate { c ->
        (c["name"] as String) to c["joins"].asListOfMaps().associate { j ->
            val n = j["name"] as String; n to n
        }
    }

    /** Follow a view `join_path` (e.g. "people.zones") to the cube it lands on. */
    private fun resolveJoinPath(path: String): String {
        val parts = path.split(".")
        var cube = parts.first()
        require(cube in cubeNames) { "unknown base cube '$cube' in join_path '$path'" }
        for (seg in parts.drop(1)) {
            cube = joins[cube]?.get(seg)
                ?: error("join_path '$path': cube '$cube' has no join '$seg'")
        }
        return cube
    }

    @Test
    fun views_includeOnlyRealMembers() {
        val problems = mutableListOf<String>()
        for (view in model["views"].asListOfMaps()) {
            val vName = view["name"] as String
            for (entry in view["cubes"].asListOfMaps()) {
                val path = entry["join_path"] as String
                val cube = runCatching { resolveJoinPath(path) }
                    .getOrElse { problems += "view '$vName': ${it.message}"; continue }
                val real = members[cube].orEmpty()
                for (inc in entry["includes"].asListOfStrings()) {
                    if (inc !in real) {
                        problems += "view '$vName': include '$inc' does not exist on cube '$cube' " +
                            "(via join_path '$path')"
                    }
                }
            }
        }
        assertTrue("Semantic layer view references are broken:\n${problems.joinToString("\n")}", problems.isEmpty())
    }

    @Test
    fun functionResolveTargets_pointAtRealDimensions() {
        val problems = mutableListOf<String>()
        for (fn in functions["functions"].asListOfMaps()) {
            val fName = fn["name"] as String
            for (arg in fn["arguments"].asListOfMaps()) {
                val target = arg["resolves"] as? String ?: continue
                val cube = target.substringBefore('.')
                val dim = target.substringAfter('.', "")
                when {
                    cube !in cubeNames ->
                        problems += "function '$fName': resolves '$target' -> unknown cube '$cube'"
                    dim.isNotEmpty() && dim !in members[cube].orEmpty() ->
                        problems += "function '$fName': resolves '$target' -> '$dim' not a member of cube '$cube'"
                }
            }
        }
        assertTrue("Function resolve targets are broken:\n${problems.joinToString("\n")}", problems.isEmpty())
    }

    @Test
    fun joinTargets_referenceRealCubes() {
        val problems = mutableListOf<String>()
        for ((cube, cubeJoins) in joins) {
            for (target in cubeJoins.values) {
                if (target !in cubeNames) problems += "cube '$cube' joins unknown cube '$target'"
            }
        }
        assertTrue("Joins reference unknown cubes:\n${problems.joinToString("\n")}", problems.isEmpty())
    }

    // --- helpers -------------------------------------------------------------------------------

    @Suppress("UNCHECKED_CAST")
    private fun Any?.asListOfMaps(): List<Map<String, Any?>> =
        (this as? List<*>)?.map { it as Map<String, Any?> } ?: emptyList()

    private fun Any?.asListOfStrings(): List<String> =
        (this as? List<*>)?.map { it as String } ?: emptyList()

    @Suppress("UNCHECKED_CAST")
    private fun load(name: String): Map<String, Any?> =
        Yaml().load(repoFile("semantic/$name").readText()) as Map<String, Any?>

    private fun repoFile(relative: String): File {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null) {
            if (File(dir, "semantic/meridian.yml").exists()) return File(dir, relative)
            dir = dir.parentFile
        }
        error("Could not locate repo root (semantic/meridian.yml) from ${System.getProperty("user.dir")}")
    }
}
