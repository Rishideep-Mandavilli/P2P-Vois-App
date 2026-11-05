# Vois autonomous relay and presentation suite
import os
import matplotlib.pyplot as plt
import matplotlib.patches as patches
import numpy as np
from PIL import Image

os.makedirs('slide_assets', exist_ok=True)

# Set high DPI and aesthetic styling
plt.rcParams['font.sans-serif'] = 'Helvetica', 'Arial', 'DejaVu Sans'
plt.rcParams['axes.edgecolor'] = '#334155'
plt.rcParams['axes.linewidth'] = 0.8

# -------------------------------------------------------------
# 1. Scope & Market Diagram (problem_scope.png)
# -------------------------------------------------------------
def make_scope_diagram():
    fig, ax = plt.subplots(figsize=(7.5, 4.5), dpi=200)
    fig.patch.set_facecolor('#0f172a')
    ax.set_facecolor('#0f172a')

    # Market Circles (TAM / SAM / SOM)
    circles = [
        (0.32, 0.5, 0.44, '#1e293b', '#3b82f6', 'TAM: $22.4B\nGlobal Disaster Tech & Critical Comms', (0.32, 0.83)),
        (0.32, 0.5, 0.30, '#1e3a5f', '#10b981', 'SAM: $4.2B\nOff-Grid & Workforce Comms', (0.32, 0.68)),
        (0.32, 0.5, 0.16, '#064e3b', '#34d399', 'SOM: $380M\nRegional Public Safety', (0.32, 0.48)),
    ]
    for x, y, r, fc, ec, lbl, txt_pos in circles:
        c = patches.Circle((x, y), r, facecolor=fc, edgecolor=ec, linewidth=2, alpha=0.9)
        ax.add_patch(c)
        ax.text(txt_pos[0], txt_pos[1], lbl, color='#ffffff', fontsize=8.5, weight='bold',
                ha='center', va='center', bbox=dict(boxstyle='round,pad=0.2', facecolor='#0b1325', edgecolor=ec, lw=1))

    # Population Stats Box
    ax.text(0.78, 0.85, 'AFFECTED POPULATIONS', color='#38bdf8', fontsize=10, weight='bold', ha='center')
    
    stats = [
        ('200M+', 'Annual Disaster Victims\n(Floods, Cyclones, Quakes)', '#ef4444'),
        ('50M+', 'Crowd Surge Exposures\n(Festivals, Marathons, Rallies)', '#f59e0b'),
        ('30M+', 'Industrial Dead Zones\n(Mines, Tunnels, Basements)', '#10b981'),
    ]
    
    y_pos = 0.68
    for num, desc, col in stats:
        rect = patches.FancyBboxPatch((0.59, y_pos - 0.08), 0.38, 0.14,
                                      boxstyle="round,pad=0.02,rounding_size=0.03",
                                      facecolor='#1e293b', edgecolor=col, linewidth=1.5)
        ax.add_patch(rect)
        ax.text(0.61, y_pos + 0.01, num, color=col, fontsize=13, weight='bold', va='center')
        ax.text(0.74, y_pos - 0.01, desc, color='#cbd5e1', fontsize=7.5, va='center')
        y_pos -= 0.17

    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis('off')
    plt.tight_layout()
    plt.savefig('slide_assets/problem_scope.png', facecolor=fig.get_facecolor(), edgecolor='none', bbox_inches='tight')
    plt.close()

# -------------------------------------------------------------
# 2. Architecture & Relay Diagram (solution_architecture.png)
# -------------------------------------------------------------
def make_architecture_diagram():
    fig, ax = plt.subplots(figsize=(8.0, 4.2), dpi=200)
    fig.patch.set_facecolor('#0f172a')
    ax.set_facecolor('#0f172a')

    # Nodes
    nodes = [
        (0.14, 0.5, 'CALLER / VICTIM\n(Trapped Phone)', '#3b82f6', 'Mic -> 16kHz PCM\n8-bit ADPCM Encode\nEncrypted Payload'),
        (0.50, 0.5, 'VOLUNTEER RELAY\n(Middle Phone)', '#10b981', 'ZERO-CPU Forwarding\nUndecoded Raw Bytes\nPreserves Battery!'),
        (0.86, 0.5, 'RESPONDER\n(Rescue Team)', '#f59e0b', 'ADPCM Decode\n40ms Jitter Buffer\nSpeaker Playback'),
    ]

    for x, y, title, col, detail in nodes:
        box = patches.FancyBboxPatch((x - 0.12, y - 0.28), 0.24, 0.56,
                                     boxstyle="round,pad=0.02,rounding_size=0.04",
                                     facecolor='#1e293b', edgecolor=col, linewidth=2)
        ax.add_patch(box)
        # Header inside box
        ax.text(x, y + 0.18, title, color='#ffffff', fontsize=9, weight='bold', ha='center', va='center')
        ax.axhline(0, color=col)
        # Inner detail box
        detail_box = patches.FancyBboxPatch((x - 0.105, y - 0.24), 0.21, 0.34,
                                            boxstyle="round,pad=0.01,rounding_size=0.02",
                                            facecolor='#0b1325', edgecolor='#334155', linewidth=1)
        ax.add_patch(detail_box)
        ax.text(x, y - 0.07, detail, color='#94a3b8', fontsize=7.2, ha='center', va='center', multialignment='center')

    # Connecting Links (Arrows)
    # Link 1
    ax.annotate('', xy=(0.375, 0.58), xytext=(0.265, 0.58),
                arrowprops=dict(arrowstyle="->", color='#38bdf8', lw=2.5, mutation_scale=15))
    ax.annotate('', xy=(0.265, 0.42), xytext=(0.375, 0.42),
                arrowprops=dict(arrowstyle="->", color='#38bdf8', lw=2.5, mutation_scale=15))
    ax.text(0.32, 0.65, 'Wi-Fi Direct P2P\n(~50m Range)', color='#38bdf8', fontsize=7.5, weight='bold', ha='center')
    ax.text(0.32, 0.35, 'Full-Duplex Sockets', color='#64748b', fontsize=6.8, ha='center')

    # Link 2
    ax.annotate('', xy=(0.735, 0.58), xytext=(0.625, 0.58),
                arrowprops=dict(arrowstyle="->", color='#10b981', lw=2.5, mutation_scale=15))
    ax.annotate('', xy=(0.625, 0.42), xytext=(0.735, 0.42),
                arrowprops=dict(arrowstyle="->", color='#10b981', lw=2.5, mutation_scale=15))
    ax.text(0.68, 0.65, 'Bluetooth Fallback\n(Dual RFCOMM Tunnels)', color='#10b981', fontsize=7.5, weight='bold', ha='center')
    ax.text(0.68, 0.35, 'No Interference', color='#64748b', fontsize=6.8, ha='center')

    # Bottom Callout banner: Emergency SOS
    sos_banner = patches.FancyBboxPatch((0.08, 0.04), 0.84, 0.12,
                                       boxstyle="round,pad=0.01,rounding_size=0.03",
                                       facecolor='#450a0a', edgecolor='#ef4444', linewidth=1.5)
    ax.add_patch(sos_banner)
    ax.text(0.5, 0.10, 'EMERGENCY SOS OVERRIDE: 6 Coded Beacons + GPS Fix | Bypasses Do Not Disturb | Forces Max Siren Volume',
            color='#fca5a5', fontsize=7.8, weight='bold', ha='center', va='center')

    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis('off')
    plt.tight_layout()
    plt.savefig('slide_assets/solution_architecture.png', facecolor=fig.get_facecolor(), edgecolor='none', bbox_inches='tight')
    plt.close()

# -------------------------------------------------------------
# 3. GTM Strategy Diagram (gtm_funnel.png)
# -------------------------------------------------------------
def make_gtm_diagram():
    fig, ax = plt.subplots(figsize=(7.5, 4.3), dpi=200)
    fig.patch.set_facecolor('#0f172a')
    ax.set_facecolor('#0f172a')

    stages = [
        ('PHASE 1: Institutional B2G & NGO Pilots',
         'Partner with NDMA/SDMA, Red Cross, and Civil Defense forces for flood/cyclone drill validation.',
         '#3b82f6', 0.82),
        ('PHASE 2: Mass Event & Crowd Deployments',
         'Deploy as perimeter communication tool for marathons, festivals, and religious pilgrimages.',
         '#10b981', 0.52),
        ('PHASE 3: Viral Offline Peer-to-Peer APK Sharing',
         'Built-in radio APK-beamer allows one user to install the app on 100+ nearby phones in minutes.',
         '#8b5cf6', 0.22),
    ]

    for title, desc, col, y in stages:
        # Step card
        card = patches.FancyBboxPatch((0.05, y - 0.10), 0.90, 0.20,
                                      boxstyle="round,pad=0.02,rounding_size=0.03",
                                      facecolor='#1e293b', edgecolor=col, linewidth=2)
        ax.add_patch(card)
        # Tag pill
        pill = patches.FancyBboxPatch((0.08, y + 0.02), 0.38, 0.06,
                                      boxstyle="round,pad=0.01,rounding_size=0.02",
                                      facecolor=col, edgecolor='none')
        ax.add_patch(pill)
        ax.text(0.27, y + 0.05, title.split(':')[0], color='#ffffff', fontsize=8, weight='bold', ha='center', va='center')
        ax.text(0.48, y + 0.05, title.split(':')[1], color='#ffffff', fontsize=8.5, weight='bold', va='center')
        ax.text(0.08, y - 0.05, desc, color='#cbd5e1', fontsize=8.0, va='center')

    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis('off')
    plt.tight_layout()
    plt.savefig('slide_assets/gtm_funnel.png', facecolor=fig.get_facecolor(), edgecolor='none', bbox_inches='tight')
    plt.close()

# -------------------------------------------------------------
# 4. Roadmap Diagram (roadmap_timeline.png)
# -------------------------------------------------------------
def make_roadmap_diagram():
    fig, ax = plt.subplots(figsize=(7.5, 4.3), dpi=200)
    fig.patch.set_facecolor('#0f172a')
    ax.set_facecolor('#0f172a')

    # Main timeline axis
    ax.plot([0.1, 0.9], [0.5, 0.5], color='#334155', lw=4, zorder=1)

    phases = [
        (0.22, 'MONTHS 1 - 2', 'Foundation & Radio Sockets',
         ['Raw AOSP Wi-Fi P2P & BT Classic',
          'Unified ByteChannel abstraction',
          'Android Foreground Service keep-alive'],
         '#3b82f6'),
        (0.50, 'MONTHS 3 - 4', 'Voice Codec & SOS Systems',
         ['Opus 8-12 kbps codec integration',
          'Store-and-forward SOS queue',
          'Hardware volume & DND siren override'],
         '#10b981'),
        (0.78, 'MONTHS 5 - 6', 'Relay Depth & Field Pilots',
         ['Undecoded 3-node relay validation',
          'Pilot trial with 100+ responders',
          'Target: 25,000 public beta installs'],
         '#f59e0b'),
    ]

    for x, time_lbl, phase_name, bullets, col in phases:
        # Timeline node circle
        circle = patches.Circle((x, 0.5), 0.04, facecolor=col, edgecolor='#ffffff', lw=2, zorder=3)
        ax.add_patch(circle)
        
        # Time badge
        ax.text(x, 0.60, time_lbl, color=col, fontsize=9, weight='bold', ha='center',
                bbox=dict(boxstyle='round,pad=0.2', facecolor='#1e293b', edgecolor=col, lw=1))
        
        # Card below
        card = patches.FancyBboxPatch((x - 0.12, 0.08), 0.24, 0.34,
                                      boxstyle="round,pad=0.01,rounding_size=0.02",
                                      facecolor='#1e293b', edgecolor=col, linewidth=1.5)
        ax.add_patch(card)
        ax.text(x, 0.36, phase_name, color='#ffffff', fontsize=8, weight='bold', ha='center')
        
        b_y = 0.28
        for b in bullets:
            ax.text(x - 0.10, b_y, f"• {b}", color='#cbd5e1', fontsize=6.8, va='center')
            b_y -= 0.08

    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis('off')
    plt.tight_layout()
    plt.savefig('slide_assets/roadmap_timeline.png', facecolor=fig.get_facecolor(), edgecolor='none', bbox_inches='tight')
    plt.close()

if __name__ == '__main__':
    make_scope_diagram()
    make_architecture_diagram()
    make_gtm_diagram()
    make_roadmap_diagram()
    print("All diagrams generated successfully.")
