package com.wireguard.android.activity

import android.os.Bundle
import android.view.LayoutInflater
import android.view.MenuItem
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.wireguard.android.Application
import com.wireguard.android.R
import com.wireguard.android.util.UserKnobs
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

class TunnelSwitchSettingsActivity : AppCompatActivity() {

    private data class TunnelItem(val name: String, var enabled: Boolean)

    private inner class TunnelSwitchAdapter(
        private val items: MutableList<TunnelItem>
    ) : RecyclerView.Adapter<TunnelSwitchAdapter.ViewHolder>() {

        inner class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
            val cbEnabled: CheckBox = view.findViewById(R.id.cb_enabled)
            val tvName: TextView = view.findViewById(R.id.tv_tunnel_name)
            val btnUp: Button = view.findViewById(R.id.btn_move_up)
            val btnDown: Button = view.findViewById(R.id.btn_move_down)
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
            val view = LayoutInflater.from(parent.context)
                .inflate(R.layout.tunnel_switch_item, parent, false)
            return ViewHolder(view)
        }

        override fun onBindViewHolder(holder: ViewHolder, position: Int) {
            val item = items[position]
            holder.tvName.text = item.name
            holder.cbEnabled.isChecked = item.enabled
            holder.cbEnabled.setOnCheckedChangeListener { _, checked ->
                items[holder.bindingAdapterPosition].enabled = checked
            }
            holder.btnUp.isEnabled = position > 0
            holder.btnDown.isEnabled = position < items.size - 1
            holder.btnUp.setOnClickListener {
                val pos = holder.bindingAdapterPosition
                if (pos > 0) {
                    items.add(pos - 1, items.removeAt(pos))
                    notifyItemMoved(pos, pos - 1)
                    notifyItemChanged(pos - 1)
                    notifyItemChanged(pos)
                }
            }
            holder.btnDown.setOnClickListener {
                val pos = holder.bindingAdapterPosition
                if (pos < items.size - 1) {
                    items.add(pos + 1, items.removeAt(pos))
                    notifyItemMoved(pos, pos + 1)
                    notifyItemChanged(pos)
                    notifyItemChanged(pos + 1)
                }
            }
        }

        override fun getItemCount() = items.size
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.tunnel_switch_settings_activity)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)

        val rootLayout = findViewById<LinearLayout>(R.id.root_layout)
        ViewCompat.setOnApplyWindowInsetsListener(rootLayout) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }

        val etCheckInterval = findViewById<EditText>(R.id.et_check_interval)
        val etMaxCycles = findViewById<EditText>(R.id.et_max_cycles)
        val rvTunnels = findViewById<RecyclerView>(R.id.rv_tunnels)
        val btnSave = findViewById<Button>(R.id.btn_save)

        val items = mutableListOf<TunnelItem>()
        val adapter = TunnelSwitchAdapter(items)
        rvTunnels.layoutManager = LinearLayoutManager(this)
        rvTunnels.adapter = adapter

        lifecycleScope.launch {
            val tunnelManager = Application.getTunnelManager()
            val tunnels = tunnelManager.getTunnels()
            val savedOrder = UserKnobs.tunnelSwitchOrder.first()
            val checkInterval = UserKnobs.tunnelSwitchCheckInterval.first()
            val maxCycles = UserKnobs.tunnelSwitchMaxCycles.first()

            etCheckInterval.setText(checkInterval.toString())
            etMaxCycles.setText(maxCycles.toString())

            val allNames = tunnels.map { it.name }
            val ordered = mutableListOf<TunnelItem>()
            for (name in savedOrder) {
                if (allNames.contains(name)) ordered.add(TunnelItem(name, true))
            }
            for (name in allNames) {
                if (savedOrder.none { it == name }) ordered.add(TunnelItem(name, false))
            }

            items.addAll(ordered)
            adapter.notifyDataSetChanged()
        }

        btnSave.setOnClickListener {
            lifecycleScope.launch {
                val checkInterval = etCheckInterval.text.toString().toIntOrNull()?.coerceAtLeast(5) ?: 60
                val maxCycles = etMaxCycles.text.toString().toIntOrNull()?.coerceAtLeast(0) ?: 0
                val order = items.filter { it.enabled }.map { it.name }
                UserKnobs.setTunnelSwitchCheckInterval(checkInterval)
                UserKnobs.setTunnelSwitchMaxCycles(maxCycles)
                UserKnobs.setTunnelSwitchOrder(order)
                finish()
            }
        }
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        if (item.itemId == android.R.id.home) {
            finish()
            return true
        }
        return super.onOptionsItemSelected(item)
    }
}
