package com.example.feature.worldclock

import android.content.Context
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import org.json.JSONArray
import org.json.JSONObject

/** Land fill + the country/coastline border mesh, both in unit space (u,v ∈ [0,1]). */
data class WorldGeometry(val land: Path, val borders: Path)

/**
 * Decodes the bundled `countries-110m` world-atlas TopoJSON for the flat Vector map style (§5.2).
 * Native equivalent of `topojson-client` + `d3.geoEquirectangular()`: arcs are delta-decoded and
 * de-quantized to lng/lat with the topology's `transform`, then projected with the same
 * equirectangular mapping [DayNightMap] already uses — emitted in unit space so the caller can fit
 * the cached paths to any canvas size with one transform instead of re-projecting per frame.
 *
 * Two paths come out: [WorldGeometry.land] (filled continents, from the topology's `land` object)
 * and [WorldGeometry.borders] (every arc drawn once — coastlines plus interior country borders,
 * which is the de-duplicated mesh since a topology stores each shared boundary as a single arc).
 *
 * No d3 / WebView: the projection is one linear formula and the whole asset is ~108 KB, decoded once.
 */
object WorldAtlas {

    fun load(context: Context): WorldGeometry? = runCatching {
        val raw = context.assets.open("countries-110m.json").bufferedReader().use { it.readText() }
        val topo = JSONObject(raw)

        val transform = topo.getJSONObject("transform")
        val scale = transform.getJSONArray("scale")
        val translate = transform.getJSONArray("translate")
        val sx = scale.getDouble(0); val sy = scale.getDouble(1)
        val tx = translate.getDouble(0); val ty = translate.getDouble(1)

        // Decode every arc once: delta-accumulate the quantized integers, de-quantize to lng/lat,
        // then project to unit space. arcsUv[i] is arc i as a list of (u,v) points.
        val arcsJson = topo.getJSONArray("arcs")
        val arcsUv = ArrayList<List<Offset>>(arcsJson.length())
        for (i in 0 until arcsJson.length()) {
            val arc = arcsJson.getJSONArray(i)
            var x = 0L; var y = 0L
            val pts = ArrayList<Offset>(arc.length())
            for (j in 0 until arc.length()) {
                val p = arc.getJSONArray(j)
                x += p.getLong(0); y += p.getLong(1)
                val lng = x * sx + tx
                val lat = y * sy + ty
                pts.add(Offset(((lng + 180.0) / 360.0).toFloat(), ((90.0 - lat) / 180.0).toFloat()))
            }
            arcsUv.add(pts)
        }

        // Land fill — the topology's `land` object (continents merged, no interior lines).
        val landPath = Path()
        val land = topo.getJSONObject("objects").getJSONObject("land")
        val geometries = land.getJSONArray("geometries")
        for (g in 0 until geometries.length()) {
            addGeometry(landPath, geometries.getJSONObject(g), arcsUv)
        }

        // Border mesh — every arc once. Coastlines + shared country boundaries, de-duplicated for
        // free because the topology stores each boundary as exactly one arc.
        val borderPath = Path()
        for (i in arcsUv.indices) {
            val arc = arcsUv[i]
            if (arc.isEmpty()) continue
            borderPath.moveTo(arc[0].x, arc[0].y)
            for (m in 1 until arc.size) borderPath.lineTo(arc[m].x, arc[m].y)
        }

        WorldGeometry(landPath, borderPath)
    }.getOrNull()

    /** Add one geometry's fill: Polygon (rings) or MultiPolygon (polygons → rings). */
    private fun addGeometry(path: Path, geom: JSONObject, arcsUv: List<List<Offset>>) {
        when (geom.getString("type")) {
            "Polygon" -> {
                val rings = geom.getJSONArray("arcs")
                for (r in 0 until rings.length()) addRing(path, rings.getJSONArray(r), arcsUv)
            }
            "MultiPolygon" -> {
                val polygons = geom.getJSONArray("arcs")
                for (p in 0 until polygons.length()) {
                    val rings = polygons.getJSONArray(p)
                    for (r in 0 until rings.length()) addRing(path, rings.getJSONArray(r), arcsUv)
                }
            }
        }
    }

    /** Stitch a ring's arcs (negative index ⇒ that arc reversed) into one closed sub-path. */
    private fun addRing(path: Path, ring: JSONArray, arcsUv: List<List<Offset>>) {
        var started = false
        for (k in 0 until ring.length()) {
            val idx = ring.getInt(k)
            val arc = if (idx >= 0) arcsUv[idx] else arcsUv[idx.inv()].asReversed()
            for (m in arc.indices) {
                // Skip the first point of every arc after the first: it duplicates the previous
                // arc's last point (TopoJSON arcs share endpoints).
                if (m == 0 && started) continue
                val pt = arc[m]
                if (!started) {
                    path.moveTo(pt.x, pt.y)
                    started = true
                } else {
                    path.lineTo(pt.x, pt.y)
                }
            }
        }
        if (started) path.close()
    }
}
