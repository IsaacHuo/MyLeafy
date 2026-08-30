package com.myleafy.android.core.campus

import com.myleafy.android.core.network.CampusIdentity
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Single source of truth for the identity boundary used by navigation, Room and services.
 * A signed-out scope intentionally has no capabilities and cannot see another identity's data.
 */
data class ActiveAppScope(
    val campusId: CampusID?,
    val eduId: String?,
    val scopeKey: String,
    val isGuest: Boolean,
    val capabilities: Set<String>,
) {
    fun supports(capability: String): Boolean = capability in capabilities

    companion object {
        val SignedOut = ActiveAppScope(
            campusId = null,
            eduId = null,
            scopeKey = "signed-out",
            isGuest = false,
            capabilities = emptySet(),
        )
    }
}

class ActiveAppScopeStore(initial: ActiveAppScope = ActiveAppScope.SignedOut) {
    private val mutableScope = MutableStateFlow(initial)
    val scope: StateFlow<ActiveAppScope> = mutableScope.asStateFlow()
    val current: ActiveAppScope get() = mutableScope.value

    fun activate(identity: CampusIdentity) {
        val descriptor = CampusDescriptor.forCampus(identity.campusId)
        mutableScope.value = ActiveAppScope(
            campusId = identity.campusId,
            eduId = identity.eduId,
            scopeKey = identity.scopeKey,
            isGuest = false,
            capabilities = descriptor.capabilities,
        )
    }

    fun activateGuest(scopeKey: String) {
        require(scopeKey.isNotBlank()) { "Guest scopeKey must not be blank" }
        mutableScope.value = ActiveAppScope(
            campusId = CampusID.guest,
            eduId = null,
            scopeKey = scopeKey,
            isGuest = true,
            capabilities = CampusDescriptor.guest.capabilities,
        )
    }

    fun clear() {
        mutableScope.value = ActiveAppScope.SignedOut
    }
}
