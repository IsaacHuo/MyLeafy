package com.myleafy.android.features.timetable.weather

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import androidx.core.content.ContextCompat
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.HttpUrl.Companion.toHttpUrl
import kotlin.coroutines.resume

data class WeatherSnapshot(
    val temperatureCelsius: Double,
    val condition: WeatherCondition,
    val observedAt: Instant,
    val isStale: Boolean,
)

enum class WeatherCondition(val label: String) {
    CLEAR("晴"), CLOUDY("多云"), OVERCAST("阴"), FOG("雾"), DRIZZLE("小雨"),
    RAIN("雨"), SNOW("雪"), THUNDERSTORM("雷雨"), UNKNOWN("天气"),
}

sealed interface WeatherUiState {
    data object Idle : WeatherUiState
    data object Loading : WeatherUiState
    data class Loaded(val snapshot: WeatherSnapshot) : WeatherUiState
    data class Error(val message: String) : WeatherUiState
}

class DeviceLocationProvider(private val context: Context) {
    private val manager = context.getSystemService(LocationManager::class.java)

    fun hasPermission(): Boolean = ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.ACCESS_COARSE_LOCATION,
    ) == PackageManager.PERMISSION_GRANTED

    @SuppressLint("MissingPermission")
    @Suppress("DEPRECATION")
    suspend fun currentLocation(): Location? {
        if (!hasPermission()) return null
        val providers = listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER)
            .filter(manager::isProviderEnabled)
        val recent = providers.mapNotNull(manager::getLastKnownLocation)
            .maxByOrNull(Location::getTime)
            ?.takeIf { System.currentTimeMillis() - it.time <= LAST_LOCATION_MAX_AGE_MILLIS }
        if (recent != null) return recent
        val provider = providers.firstOrNull() ?: return null
        return withTimeoutOrNull(LOCATION_TIMEOUT_MILLIS) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                suspendCancellableCoroutine { continuation ->
                    manager.getCurrentLocation(provider, null, context.mainExecutor) { location ->
                        if (continuation.isActive) continuation.resume(location)
                    }
                }
            } else {
                suspendCancellableCoroutine { continuation ->
                    val listener = object : LocationListener {
                        override fun onLocationChanged(location: Location) {
                            manager.removeUpdates(this)
                            if (continuation.isActive) continuation.resume(location)
                        }
                    }
                    continuation.invokeOnCancellation { manager.removeUpdates(listener) }
                    manager.requestSingleUpdate(provider, listener, null)
                }
            }
        }
    }

    private companion object {
        const val LOCATION_TIMEOUT_MILLIS = 10_000L
        const val LAST_LOCATION_MAX_AGE_MILLIS = 30 * 60 * 1000L
    }
}

class WeatherRepository(
    context: Context,
    private val locationProvider: DeviceLocationProvider = DeviceLocationProvider(context),
    private val client: OkHttpClient = OkHttpClient(),
) {
    private val cache = context.getSharedPreferences("weather_cache", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }

    fun hasLocationPermission(): Boolean = locationProvider.hasPermission()

    suspend fun currentWeather(forceRefresh: Boolean = false): WeatherSnapshot = withContext(Dispatchers.IO) {
        val cached = readCache()
        if (!forceRefresh && cached != null && age(cached) <= FRESH_AGE) return@withContext cached
        val location = locationProvider.currentLocation()
            ?: return@withContext cached?.takeIf { age(it) <= STALE_AGE }?.copy(isStale = true)
            ?: error("无法获取当前位置")
        runCatching { fetch(location) }.getOrElse { error ->
            cached?.takeIf { age(it) <= STALE_AGE }?.copy(isStale = true)
                ?: throw error
        }
    }

    private fun fetch(location: Location): WeatherSnapshot {
        val url = "https://api.open-meteo.com/v1/forecast".toHttpUrl().newBuilder()
            .addQueryParameter("latitude", location.latitude.toString())
            .addQueryParameter("longitude", location.longitude.toString())
            .addQueryParameter("current", "temperature_2m,weather_code")
            .addQueryParameter("timezone", "auto")
            .build()
        val body = client.newCall(Request.Builder().url(url).get().build()).execute().use { response ->
            if (!response.isSuccessful) error("天气服务返回 ${response.code}")
            response.body?.string() ?: error("天气服务返回空响应")
        }
        val payload = json.decodeFromString<OpenMeteoResponse>(body)
        val current = payload.current ?: error("天气服务缺少当前天气")
        val snapshot = WeatherSnapshot(
            temperatureCelsius = current.temperature,
            condition = conditionFor(current.weatherCode),
            observedAt = Instant.now(),
            isStale = false,
        )
        writeCache(snapshot)
        return snapshot
    }

    private fun readCache(): WeatherSnapshot? {
        if (!cache.contains(KEY_TEMPERATURE)) return null
        val observedAt = cache.getLong(KEY_OBSERVED_AT, 0L).takeIf { it > 0L } ?: return null
        return WeatherSnapshot(
            temperatureCelsius = Double.fromBits(cache.getLong(KEY_TEMPERATURE, 0L)),
            condition = cache.getString(KEY_CONDITION, null)?.let {
                runCatching { WeatherCondition.valueOf(it) }.getOrNull()
            } ?: WeatherCondition.UNKNOWN,
            observedAt = Instant.ofEpochMilli(observedAt),
            isStale = false,
        )
    }

    private fun writeCache(snapshot: WeatherSnapshot) {
        cache.edit()
            .putLong(KEY_TEMPERATURE, snapshot.temperatureCelsius.toBits())
            .putString(KEY_CONDITION, snapshot.condition.name)
            .putLong(KEY_OBSERVED_AT, snapshot.observedAt.toEpochMilli())
            .apply()
    }

    private fun age(snapshot: WeatherSnapshot): Duration = Duration.between(snapshot.observedAt, Instant.now())

    private fun conditionFor(code: Int): WeatherCondition = when (code) {
        0 -> WeatherCondition.CLEAR
        1, 2 -> WeatherCondition.CLOUDY
        3 -> WeatherCondition.OVERCAST
        45, 48 -> WeatherCondition.FOG
        in 51..57 -> WeatherCondition.DRIZZLE
        in 61..67, in 80..82 -> WeatherCondition.RAIN
        in 71..77, 85, 86 -> WeatherCondition.SNOW
        95, 96, 99 -> WeatherCondition.THUNDERSTORM
        else -> WeatherCondition.UNKNOWN
    }

    @Serializable
    private data class OpenMeteoResponse(val current: CurrentWeather? = null)

    @Serializable
    private data class CurrentWeather(
        @SerialName("temperature_2m") val temperature: Double,
        @SerialName("weather_code") val weatherCode: Int,
    )

    private companion object {
        val FRESH_AGE: Duration = Duration.ofMinutes(30)
        val STALE_AGE: Duration = Duration.ofHours(6)
        const val KEY_TEMPERATURE = "temperature"
        const val KEY_CONDITION = "condition"
        const val KEY_OBSERVED_AT = "observed_at"
    }
}
