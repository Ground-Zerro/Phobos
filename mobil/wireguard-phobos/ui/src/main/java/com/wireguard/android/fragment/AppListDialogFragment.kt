/*
 * Copyright © 2017-2025 WireGuard LLC. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
package com.wireguard.android.fragment

import android.Manifest
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.PackageManager.PackageInfoFlags
import android.os.Build
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import android.widget.Toast
import androidx.databinding.Observable
import androidx.fragment.app.DialogFragment
import androidx.fragment.app.setFragmentResult
import androidx.lifecycle.lifecycleScope
import com.google.android.material.tabs.TabLayout
import com.wireguard.android.BR
import com.wireguard.android.R
import com.wireguard.android.databinding.AppListDialogFragmentBinding
import com.wireguard.android.databinding.ObservableKeyedArrayList
import com.wireguard.android.model.ApplicationData
import com.wireguard.android.util.ErrorMessages
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class AppListDialogFragment : DialogFragment() {
    private val allAppData = mutableListOf<ApplicationData>()
    private val appData = ObservableKeyedArrayList<String, ApplicationData>()
    private var currentlySelectedApps = emptyList<String>()
    private var initiallyExcluded = false
    private var searchQuery = ""
    private var hideSystemApps = false
    private var isDataLoaded = false
    private var binding: AppListDialogFragmentBinding? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        currentlySelectedApps = (arguments?.getStringArrayList(KEY_SELECTED_APPS) ?: emptyList())
        initiallyExcluded = arguments?.getBoolean(KEY_IS_EXCLUDED) ?: true
        setStyle(STYLE_NO_TITLE, R.style.AppTheme_FullScreenDialog)
    }

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        val b = AppListDialogFragmentBinding.inflate(inflater, container, false)
        b.appData = appData
        binding = b
        return b.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        val b = binding ?: return

        b.tabs.apply {
            selectTab(getTabAt(if (initiallyExcluded) 0 else 1))
            addOnTabSelectedListener(object : TabLayout.OnTabSelectedListener {
                override fun onTabReselected(tab: TabLayout.Tab?) = Unit
                override fun onTabUnselected(tab: TabLayout.Tab?) = Unit
                override fun onTabSelected(tab: TabLayout.Tab?) = updateApplyButton()
            })
        }

        b.searchInput.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = Unit
            override fun afterTextChanged(s: Editable?) {
                searchQuery = s?.toString() ?: ""
                applyFilter()
            }
        })

        b.hideSystemAppsCheckbox.setOnCheckedChangeListener { _, isChecked ->
            hideSystemApps = isChecked
            applyFilter()
        }

        b.btnCancel.setOnClickListener { dismiss() }
        b.btnApply.setOnClickListener { setSelectionAndDismiss() }

        updateApplyButton()
        loadData()
    }

    override fun onStart() {
        super.onStart()
        dialog?.window?.apply {
            setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            @Suppress("DEPRECATION")
            setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
            WindowCompat.setDecorFitsSystemWindows(this, false)
        }
        binding?.root?.let { root ->
            ViewCompat.setOnApplyWindowInsetsListener(root) { v, insets ->
                val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
                v.setPadding(v.paddingLeft, systemBars.top, v.paddingRight, systemBars.bottom)
                insets
            }
        }
    }

    override fun onDestroyView() {
        binding = null
        super.onDestroyView()
    }

    private fun applyFilter() {
        val query = searchQuery.trim()
        val filtered = allAppData.filter { app ->
            (!hideSystemApps || !app.isSystem) &&
                (query.isEmpty() || app.name.contains(query, ignoreCase = true))
        }
        appData.clear()
        appData.addAll(filtered)
        binding?.progressBar?.visibility = if (isDataLoaded) View.GONE else View.VISIBLE
        updateApplyButton()
    }

    private fun loadData() {
        val activity = activity ?: return
        val pm = activity.packageManager
        lifecycleScope.launch(Dispatchers.Default) {
            try {
                val loaded = mutableListOf<ApplicationData>()
                withContext(Dispatchers.IO) {
                    val packageInfos = getPackagesHoldingPermissions(pm, arrayOf(Manifest.permission.INTERNET))
                    packageInfos.forEach {
                        val packageName = it.packageName
                        val appInfo = it.applicationInfo ?: return@forEach
                        val isSystem = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
                        val item = ApplicationData(
                            appInfo.loadIcon(pm),
                            appInfo.loadLabel(pm).toString(),
                            packageName,
                            currentlySelectedApps.contains(packageName),
                            isSystem
                        )
                        item.addOnPropertyChangedCallback(object : Observable.OnPropertyChangedCallback() {
                            override fun onPropertyChanged(sender: Observable?, propertyId: Int) {
                                if (propertyId == BR.selected) updateApplyButton()
                            }
                        })
                        loaded.add(item)
                    }
                }
                loaded.sortWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })
                withContext(Dispatchers.Main.immediate) {
                    allAppData.clear()
                    allAppData.addAll(loaded)
                    isDataLoaded = true
                    applyFilter()
                }
            } catch (e: Throwable) {
                withContext(Dispatchers.Main.immediate) {
                    val error = ErrorMessages[e]
                    val message = activity.getString(R.string.error_fetching_apps, error)
                    Toast.makeText(activity, message, Toast.LENGTH_LONG).show()
                    dismissAllowingStateLoss()
                }
            }
        }
    }

    private fun getPackagesHoldingPermissions(pm: PackageManager, permissions: Array<String>): List<PackageInfo> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getPackagesHoldingPermissions(permissions, PackageInfoFlags.of(0L))
        } else {
            @Suppress("DEPRECATION")
            pm.getPackagesHoldingPermissions(permissions, 0)
        }
    }

    private fun updateApplyButton() {
        val b = binding ?: return
        val numSelected = allAppData.count { it.isSelected }
        b.btnApply.text = if (numSelected == 0) {
            getString(R.string.use_all_applications)
        } else when (b.tabs.selectedTabPosition) {
            0 -> resources.getQuantityString(R.plurals.exclude_n_applications, numSelected, numSelected)
            1 -> resources.getQuantityString(R.plurals.include_n_applications, numSelected, numSelected)
            else -> getString(R.string.use_all_applications)
        }
    }

    private fun setSelectionAndDismiss() {
        val b = binding ?: return
        val selectedApps = allAppData.filter { it.isSelected }.map { it.packageName }
        setFragmentResult(
            REQUEST_SELECTION,
            Bundle().apply {
                putStringArray(KEY_SELECTED_APPS, selectedApps.toTypedArray())
                putBoolean(KEY_IS_EXCLUDED, b.tabs.selectedTabPosition == 0)
            }
        )
        dismiss()
    }

    companion object {
        const val KEY_SELECTED_APPS = "selected_apps"
        const val KEY_IS_EXCLUDED = "is_excluded"
        const val REQUEST_SELECTION = "request_selection"

        fun newInstance(selectedApps: ArrayList<String?>?, isExcluded: Boolean): AppListDialogFragment {
            val extras = Bundle()
            extras.putStringArrayList(KEY_SELECTED_APPS, selectedApps)
            extras.putBoolean(KEY_IS_EXCLUDED, isExcluded)
            val fragment = AppListDialogFragment()
            fragment.arguments = extras
            return fragment
        }
    }
}
