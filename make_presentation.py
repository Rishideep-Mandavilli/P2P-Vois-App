import os
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE

def create_deck():
    prs = Presentation()
    prs.slide_width = Inches(13.333)
    prs.slide_height = Inches(7.5)

    # Color Palette Definitions
    BG_DARK = RGBColor(10, 15, 29)         # #0A0F1D
    CARD_BG = RGBColor(22, 32, 50)         # #162032
    CARD_BORDER = RGBColor(43, 59, 85)     # #2B3B55
    ACCENT_GREEN = RGBColor(16, 185, 129)  # #10B981
    ACCENT_BLUE = RGBColor(56, 189, 248)   # #38BDF8
    ACCENT_RED = RGBColor(239, 68, 68)     # #EF4444
    ACCENT_AMBER = RGBColor(245, 158, 11)  # #F59E0B
    TEXT_WHITE = RGBColor(255, 255, 255)
    TEXT_LIGHT = RGBColor(226, 232, 240)   # #E2E8F0
    TEXT_MUTED = RGBColor(148, 163, 184)   # #94A3B8

    blank_layout = prs.slide_layouts[6]

    def set_slide_background(slide):
        bg_shape = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, Inches(13.333), Inches(7.5))
        bg_shape.fill.solid()
        bg_shape.fill.fore_color.rgb = BG_DARK
        bg_shape.line.fill.background()
        return bg_shape

    def add_header(slide, tag_text, title_text, subtitle_text=""):
        # Tag pill
        tag_box = slide.shapes.add_textbox(Inches(0.8), Inches(0.4), Inches(4.0), Inches(0.4))
        tf = tag_box.text_frame
        tf.word_wrap = True
        tf.margin_top = tf.margin_bottom = tf.margin_left = tf.margin_right = 0
        p = tf.paragraphs[0]
        p.text = tag_text.upper()
        p.font.size = Pt(10)
        p.font.bold = True
        p.font.color.rgb = ACCENT_GREEN

        # Title
        title_box = slide.shapes.add_textbox(Inches(0.8), Inches(0.72), Inches(11.7), Inches(0.6))
        tf2 = title_box.text_frame
        tf2.word_wrap = True
        tf2.margin_top = tf2.margin_bottom = tf2.margin_left = tf2.margin_right = 0
        p2 = tf2.paragraphs[0]
        p2.text = title_text
        p2.font.size = Pt(22)
        p2.font.bold = True
        p2.font.color.rgb = TEXT_WHITE

        # Subtitle
        if subtitle_text:
            sub_box = slide.shapes.add_textbox(Inches(0.8), Inches(1.35), Inches(11.7), Inches(0.4))
            tf3 = sub_box.text_frame
            tf3.word_wrap = True
            tf3.margin_top = tf3.margin_bottom = tf3.margin_left = tf3.margin_right = 0
            p3 = tf3.paragraphs[0]
            p3.text = subtitle_text
            p3.font.size = Pt(12)
            p3.font.color.rgb = TEXT_MUTED

    def add_card(slide, left, top, width, height, border_col=CARD_BORDER, bg_col=CARD_BG):
        shape = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, left, top, width, height)
        shape.fill.solid()
        shape.fill.fore_color.rgb = bg_col
        shape.line.color.rgb = border_col
        shape.line.width = Pt(1.5)
        return shape

    # =========================================================================
    # SLIDE 1: TITLE SLIDE
    # =========================================================================
    s1 = prs.slides.add_slide(blank_layout)
    set_slide_background(s1)

    # Decorative top glow bar
    bar = s1.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(0.8), Inches(1.5), Inches(1.5), Inches(0.08))
    bar.fill.solid()
    bar.fill.fore_color.rgb = ACCENT_GREEN
    bar.line.fill.background()

    # Title box
    tbox = s1.shapes.add_textbox(Inches(0.8), Inches(1.8), Inches(11.7), Inches(2.5))
    tf = tbox.text_frame
    tf.word_wrap = True
    p = tf.paragraphs[0]
    p.text = "P2P VOIS"
    p.font.size = Pt(48)
    p.font.bold = True
    p.font.color.rgb = TEXT_WHITE

    p2 = tf.add_paragraph()
    p2.text = "The phones in a crowd become the network, when there isn't one."
    p2.font.size = Pt(20)
    p2.font.color.rgb = ACCENT_BLUE
    p2.space_before = Pt(10)

    p3 = tf.add_paragraph()
    p3.text = "Startup Project Proposal: Offline Peer-to-Peer Voice Calling & Emergency Distress Network"
    p3.font.size = Pt(14)
    p3.font.color.rgb = TEXT_MUTED
    p3.space_before = Pt(8)

    # 3 Summary Highlight Cards across the bottom
    cards_data = [
        ("ZERO INFRASTRUCTURE", "Works with no cellular, no internet, no router, no SIM, and no server.", ACCENT_GREEN),
        ("VOICE-FIRST DESIGN", "Instant full-duplex calling & PTT walkie-talkie for panicked & low-literacy users.", ACCENT_BLUE),
        ("LIFE-SAVING SOS", "DND-bypassing siren, GPS fix, and store-and-forward relaying over built-in radios.", ACCENT_AMBER)
    ]
    for idx, (title, desc, accent) in enumerate(cards_data):
        left = Inches(0.8 + idx * 4.0)
        top = Inches(4.7)
        c = add_card(s1, left, top, Inches(3.7), Inches(2.0), border_col=accent)
        t = s1.shapes.add_textbox(left + Inches(0.2), top + Inches(0.2), Inches(3.3), Inches(1.6))
        ctf = t.text_frame
        ctf.word_wrap = True
        cp1 = ctf.paragraphs[0]
        cp1.text = title
        cp1.font.size = Pt(13)
        cp1.font.bold = True
        cp1.font.color.rgb = accent
        cp2 = ctf.add_paragraph()
        cp2.text = desc
        cp2.font.size = Pt(11)
        cp2.font.color.rgb = TEXT_LIGHT
        cp2.space_before = Pt(8)

    # =========================================================================
    # SLIDE 2: THE PROBLEM
    # =========================================================================
    s2 = prs.slides.add_slide(blank_layout)
    set_slide_background(s2)
    add_header(s2, "1. Problem Statement", "Total Communication Collapse in Sudden Crises",
               "When base stations fail or crowd surges occur, 100% of conventional calling tools stop working.")

    # 4 Cards describing the core pain points
    p_cards = [
        ("Single Point of Failure",
         "Cell towers rely on power grids and physical fiber backhaul. Cyclones, floods, earthquakes, and grid failures wipe them out within minutes, creating an absolute communication vacuum.",
         ACCENT_RED),
        ("The Crowd Surge Paradox",
         "Even with functional hardware, 40,000+ people per square kilometer (stadiums, festivals, rallies) completely overwhelms spectrum capacity, triggering an artificial blackout.",
         ACCENT_AMBER),
        ("Why Existing Options Fail",
         "• WhatsApp / Phone Calls: Require internet & active SIM.\n• Walkie-Talkies: Hardware 99% of civilians do not own.\n• Satellite Pucks: Cost ₹20,000+ plus monthly subscriptions.\n• LoRa / Meshtastic: Text only; cannot support voice.",
         ACCENT_BLUE),
        ("The Deadly Communication Vacuum",
         "78% of flood and earthquake mortalities occur in the first 6 hours—when trapped victims and field volunteers cannot coordinate or signal their status across 50–200 meters.",
         ACCENT_GREEN),
    ]

    for idx, (title, desc, col) in enumerate(p_cards):
        col_idx = idx % 2
        row_idx = idx // 2
        left = Inches(0.8 + col_idx * 5.95)
        top = Inches(1.85 + row_idx * 2.55)
        add_card(s2, left, top, Inches(5.75), Inches(2.35), border_col=col)
        tb = s2.shapes.add_textbox(left + Inches(0.25), top + Inches(0.2), Inches(5.25), Inches(1.95))
        tf = tb.text_frame
        tf.word_wrap = True
        p = tf.paragraphs[0]
        p.text = title
        p.font.size = Pt(14)
        p.font.bold = True
        p.font.color.rgb = col
        p2 = tf.add_paragraph()
        p2.text = desc
        p2.font.size = Pt(11)
        p2.font.color.rgb = TEXT_LIGHT
        p2.space_before = Pt(8)

    # =========================================================================
    # SLIDE 3: SCOPE & PROBLEM SIZING
    # =========================================================================
    s3 = prs.slides.add_slide(blank_layout)
    set_slide_background(s3)
    add_header(s3, "2. Scope & Target Scale", "Who is Facing This Issue & Market Opportunity",
               "Over 1.5 Billion people globally face frequent exposure to critical communication blackouts.")

    # Left side: Text breakdown
    left_card = add_card(s3, Inches(0.8), Inches(1.85), Inches(5.6), Inches(5.1))
    tb_scope = s3.shapes.add_textbox(Inches(1.0), Inches(2.05), Inches(5.2), Inches(4.7))
    tfs = tb_scope.text_frame
    tfs.word_wrap = True

    sections = [
        ("Humanitarian & Disaster Scale:",
         "• Over 200 Million people are displaced or impacted annually by floods, cyclones, and quakes.\n• Critical relief bottleneck: families separated by 100 meters have no way to reach each other."),
        ("Mass Gatherings & Faith Events:",
         "• Events like Kumbh Mela (up to 50M+ pilgrims), Hajj (2M+), marathons, and concerts routinely experience total network saturation."),
        ("Industrial & Sub-surface Dead Zones:",
         "• 30+ Million miners, metro tunnel workers, and basement maintenance staff operate daily in radio-opaque concrete dead zones."),
        ("Financial Market Size (TAM / SAM / SOM):",
         "• TAM: $22.4B (Global Disaster Tech & Critical Comms)\n• SAM: $4.2B (Off-grid civilian & local workforce comms)\n• SOM: $380M (South Asian public safety & event market)")
    ]

    for i, (head, body) in enumerate(sections):
        p_h = tfs.paragraphs[0] if i == 0 else tfs.add_paragraph()
        p_h.text = head
        p_h.font.size = Pt(12)
        p_h.font.bold = True
        p_h.font.color.rgb = ACCENT_BLUE
        if i > 0: p_h.space_before = Pt(8)

        p_b = tfs.add_paragraph()
        p_b.text = body
        p_b.font.size = Pt(9.5)
        p_b.font.color.rgb = TEXT_LIGHT
        p_b.space_before = Pt(2)

    # Right side: Visual Diagram (problem_scope.png)
    if os.path.exists('slide_assets/problem_scope.png'):
        s3.shapes.add_picture('slide_assets/problem_scope.png', Inches(6.6), Inches(1.85), Inches(5.9), Inches(5.1))

    # =========================================================================
    # SLIDE 4: OUR PROPOSED SOLUTION
    # =========================================================================
    s4 = prs.slides.add_slide(blank_layout)
    set_slide_background(s4)
    add_header(s4, "3. Our Proposed Solution", "P2P Vois: The Autonomous Phone-to-Phone Network",
               "Software-only innovation that unlocks the Wi-Fi Direct and Bluetooth radios already in people's pockets.")

    sol_cards = [
        ("Dual-Radio Architecture",
         "Primary: Wi-Fi Direct (~50m range, high bandwidth).\nFallback: Bluetooth Classic RFCOMM (~10m range).\nBoth sit behind a unified ByteChannel interface.",
         ACCENT_GREEN),
        ("Voice-First Design",
         "Full-duplex live calling + Hold-to-Talk Push-to-Talk (PTT).\nEssential for panicked, injured, or low-literacy users who cannot read or type text during disasters.",
         ACCENT_BLUE),
        ("Zero-CPU Undecoded Relays",
         "Middle phone forwards raw audio frames directly downstream without decoding to PCM or re-encoding.\nPreserves battery on volunteer phones.",
         ACCENT_AMBER),
        ("Pocket-Survivable SOS",
         "6 coded presets (Trapped, Medical, Fire, Flood, Need Water, Safe) + GPS fix.\nForces max volume, vibrates, and overrides Do Not Disturb.",
         ACCENT_RED),
        ("Store-and-Forward Queue",
         "Distress SOS triggered with no peer in range is queued in memory (30m TTL).\nAutomatically transmitted the millisecond a peer connects.",
         ACCENT_BLUE),
        ("Zero Infrastructure, Zero Cost",
         "Requires only two phones that pair. No cell towers, no internet, no SIM card, no server accounts, and no monthly fees.",
         ACCENT_GREEN),
    ]

    for idx, (title, desc, col) in enumerate(sol_cards):
        col_idx = idx % 3
        row_idx = idx // 3
        left = Inches(0.8 + col_idx * 3.95)
        top = Inches(1.85 + row_idx * 2.55)
        add_card(s4, left, top, Inches(3.75), Inches(2.35), border_col=col)
        tb = s4.shapes.add_textbox(left + Inches(0.2), top + Inches(0.18), Inches(3.35), Inches(2.0))
        tf = tb.text_frame
        tf.word_wrap = True
        p = tf.paragraphs[0]
        p.text = title
        p.font.size = Pt(13)
        p.font.bold = True
        p.font.color.rgb = col
        p2 = tf.add_paragraph()
        p2.text = desc
        p2.font.size = Pt(10.5)
        p2.font.color.rgb = TEXT_LIGHT
        p2.space_before = Pt(6)

    # =========================================================================
    # SLIDE 5: SYSTEM ARCHITECTURE & DATA FLOW
    # =========================================================================
    s5 = prs.slides.add_slide(blank_layout)
    set_slide_background(s5)
    add_header(s5, "Technical Blueprint", "System Architecture & Audio Pipeline Flow",
               "Designed for ultra-low latency, zero CPU waste, and maximum radio link survivability.")

    # Top diagram: solution_architecture.png
    if os.path.exists('slide_assets/solution_architecture.png'):
        s5.shapes.add_picture('slide_assets/solution_architecture.png', Inches(0.8), Inches(1.85), Inches(11.733), Inches(3.1))

    # Bottom 3 explanatory technical cards
    arch_details = [
        ("Audio Pipeline (20ms Frames)",
         "Mic -> 16 kHz mono PCM16 -> 8-bit adaptive ADPCM compression -> 323 B/frame (~129 kbps wire rate) -> 40ms jitter buffer.",
         ACCENT_BLUE),
        ("Undecoded Multi-Hop Relaying",
         "Volunteer relay phones (You -> Phone A -> Phone B) act as pure packet conduits, consuming near-zero CPU and preventing battery drain.",
         ACCENT_GREEN),
        ("Unified ByteChannel Seam",
         "Clean software abstraction: Calling engine is radio-agnostic. In the future, a multilingual speech layer can attach without modifying transports.",
         ACCENT_AMBER)
    ]

    for idx, (title, desc, col) in enumerate(arch_details):
        left = Inches(0.8 + idx * 4.0)
        top = Inches(5.15)
        add_card(s5, left, top, Inches(3.733), Inches(1.8), border_col=col)
        tb = s5.shapes.add_textbox(left + Inches(0.2), top + Inches(0.15), Inches(3.33), Inches(1.5))
        tf = tb.text_frame
        tf.word_wrap = True
        p = tf.paragraphs[0]
        p.text = title
        p.font.size = Pt(12)
        p.font.bold = True
        p.font.color.rgb = col
        p2 = tf.add_paragraph()
        p2.text = desc
        p2.font.size = Pt(10)
        p2.font.color.rgb = TEXT_LIGHT
        p2.space_before = Pt(4)

    # =========================================================================
    # SLIDE 6: BENEFICIARIES & SCOPE OF IMPACT
    # =========================================================================
    s6 = prs.slides.add_slide(blank_layout)
    set_slide_background(s6)
    add_header(s6, "4. Scope of Solution", "Who Gets Benefited & Humanitarian Impact",
               "Bridging the fatal communication gap between victims, volunteers, and emergency coordinators.")

    beneficiaries = [
        ("Trapped Civilians & Families",
         "• Reconnect with family members within 50–150m across rubble, floodwaters, or across floors.\n• Send automated SOS with GPS coordinates even with near-empty battery.",
         ACCENT_RED),
        ("First Responders (NDRF / SDRF)",
         "• Immediate local coordination channel without waiting hours for mobile cell towers (COWs) to arrive.\n• One-to-many broadcast alerts when coordinating rescue sweeps.",
         ACCENT_BLUE),
        ("Panicked & Non-Tech Civilians",
         "• Voice-first interface: hold one button to speak.\n• No typing, no complex menus, and no literacy barriers in critical moments of shock or injury.",
         ACCENT_GREEN),
        ("Event Marshals & Industrial Crews",
         "• Eliminates the need to buy or rent expensive walkie-talkie sets for hundreds of volunteers.\n• Reliable communication inside radio-opaque basements, parking cores, and mines.",
         ACCENT_AMBER),
    ]

    for idx, (title, desc, col) in enumerate(beneficiaries):
        col_idx = idx % 2
        row_idx = idx // 2
        left = Inches(0.8 + col_idx * 5.95)
        top = Inches(1.85 + row_idx * 2.55)
        add_card(s6, left, top, Inches(5.75), Inches(2.35), border_col=col)
        tb = s6.shapes.add_textbox(left + Inches(0.25), top + Inches(0.2), Inches(5.25), Inches(1.95))
        tf = tb.text_frame
        tf.word_wrap = True
        p = tf.paragraphs[0]
        p.text = title
        p.font.size = Pt(14)
        p.font.bold = True
        p.font.color.rgb = col
        p2 = tf.add_paragraph()
        p2.text = desc
        p2.font.size = Pt(11)
        p2.font.color.rgb = TEXT_LIGHT
        p2.space_before = Pt(8)

    # =========================================================================
    # SLIDE 7: GO-TO-MARKET STRATEGY (GTM)
    # =========================================================================
    s7 = prs.slides.add_slide(blank_layout)
    set_slide_background(s7)
    add_header(s7, "5. Go-To-Market Strategy", "Distribution Engine & Sustainable Business Model",
               "Combining institutional disaster adoption with hyper-local offline viral spreading.")

    # Left: GTM Funnel Diagram
    if os.path.exists('slide_assets/gtm_funnel.png'):
        s7.shapes.add_picture('slide_assets/gtm_funnel.png', Inches(0.8), Inches(1.85), Inches(6.0), Inches(5.1))

    # Right: Monetization & Growth Models
    right_card = add_card(s7, Inches(7.0), Inches(1.85), Inches(5.533), Inches(5.1))
    tb_gtm = s7.shapes.add_textbox(Inches(7.2), Inches(2.05), Inches(5.133), Inches(4.7))
    tf_gtm = tb_gtm.text_frame
    tf_gtm.word_wrap = True

    gtm_points = [
        ("Phase 1: Institutional B2G & NGO Pilots",
         "Partner with State Disaster Management Authorities (SDMA), Civil Defense, and Red Cross for official drill validation."),
        ("Phase 2: Event & Festival Safety Deployments",
         "Deploy as the coordinator tool for major marathons, religious gatherings (Kumbh, Pooram), and stadium events."),
        ("Phase 3: Viral Offline APK Beaming",
         "The app includes a built-in radio APK-beamer: one user can send the full installer to 100+ nearby phones completely offline in under 30 seconds."),
        ("Monetization Model (Dual-Tier):",
         "• Free Core Public Good: Free for individual civilians & emergency distress calls.\n• Enterprise / Municipal Tier: Custom dispatch consoles, field analytics, and dedicated encryption for industrial construction and mining.")
    ]

    for i, (head, body) in enumerate(gtm_points):
        p_h = tf_gtm.paragraphs[0] if i == 0 else tf_gtm.add_paragraph()
        p_h.text = head
        p_h.font.size = Pt(12)
        p_h.font.bold = True
        p_h.font.color.rgb = ACCENT_GREEN
        if i > 0: p_h.space_before = Pt(8)

        p_b = tf_gtm.add_paragraph()
        p_b.text = body
        p_b.font.size = Pt(10)
        p_b.font.color.rgb = TEXT_LIGHT
        p_b.space_before = Pt(2)

    # =========================================================================
    # SLIDE 8: 3 TO 6-MONTH ROADMAP & BUSINESS GROWTH
    # =========================================================================
    s8 = prs.slides.add_slide(blank_layout)
    set_slide_background(s8)
    add_header(s8, "6. Development & Growth Roadmap", "Upcoming 3 to 6-Month Execution Milestones",
               "Clear engineering sprints leading from core socket architecture to live field pilots.")

    # Timeline diagram
    if os.path.exists('slide_assets/roadmap_timeline.png'):
        s8.shapes.add_picture('slide_assets/roadmap_timeline.png', Inches(0.8), Inches(1.85), Inches(11.733), Inches(3.2))

    # Bottom growth projections
    growth_cards = [
        ("Target Milestones (Month 3)",
         "• Complete Wi-Fi Direct + BT RFCOMM sockets\n• Full-duplex live audio pipeline\n• DND-bypassing hardware SOS siren",
         ACCENT_BLUE),
        ("Target Milestones (Month 6)",
         "• Transition to Opus codec (8-12 kbps)\n• Multi-hop undecoded relay chain\n• Closed pilot with 100+ disaster volunteers",
         ACCENT_AMBER),
        ("Target User Adoption",
         "• 25,000 active beta installs\n• 3 disaster-prone district partnerships\n• 2 major public festival deployments",
         ACCENT_GREEN),
    ]

    for idx, (title, desc, col) in enumerate(growth_cards):
        left = Inches(0.8 + idx * 4.0)
        top = Inches(5.25)
        add_card(s8, left, top, Inches(3.733), Inches(1.7), border_col=col)
        tb = s8.shapes.add_textbox(left + Inches(0.2), top + Inches(0.15), Inches(3.33), Inches(1.4))
        tf = tb.text_frame
        tf.word_wrap = True
        p = tf.paragraphs[0]
        p.text = title
        p.font.size = Pt(12)
        p.font.bold = True
        p.font.color.rgb = col
        p2 = tf.add_paragraph()
        p2.text = desc
        p2.font.size = Pt(10)
        p2.font.color.rgb = TEXT_LIGHT
        p2.space_before = Pt(4)

    # =========================================================================
    # SLIDE 9: COMPETITIVE MATRIX
    # =========================================================================
    s9 = prs.slides.add_slide(blank_layout)
    set_slide_background(s9)
    add_header(s9, "Competitive Advantage", "Why P2P Vois Wins Over Traditional Alternatives",
               "A unique positioning: zero infrastructure, zero hardware cost, and voice-first reliability.")

    # Table
    rows = 6
    cols = 6
    left = Inches(0.8)
    top = Inches(1.9)
    width = Inches(11.733)
    height = Inches(4.8)

    table_shape = s9.shapes.add_table(rows, cols, left, top, width, height)
    tbl = table_shape.table

    tbl.columns[0].width = Inches(2.333)
    tbl.columns[1].width = Inches(1.88)
    tbl.columns[2].width = Inches(1.88)
    tbl.columns[3].width = Inches(1.88)
    tbl.columns[4].width = Inches(1.88)
    tbl.columns[5].width = Inches(1.88)

    table_data = [
        ["Key Metric / Feature", "Mobile Apps (WhatsApp)", "LoRa / Meshtastic", "Walkie-Talkies", "Satellite Pucks", "P2P VOIS (Ours)"],
        ["Infrastructure Required", "High (Cell / Internet)", "Low (Custom Nodes)", "Zero", "High (Satellites)", "ZERO (Phone Only)"],
        ["Hardware Cost", "₹0 (Existing phone)", "₹3,000 - ₹8,000", "₹5,000 - ₹15,000", "₹20,000 - ₹50,000", "₹0 (Existing phone)"],
        ["Monthly Fee", "Active Data Plan", "None", "None", "₹1,500 - ₹5,000/mo", "NONE (100% Free)"],
        ["Real-Time Voice Call", "Yes (Dies with net)", "NO (Text Only)", "Yes", "NO (High Latency)", "YES (Full-Duplex / PTT)"],
        ["Panic SOS Override", "No", "Basic Text", "No", "Delayed Ping", "YES (DND Siren + GPS)"]
    ]

    for r_idx, row in enumerate(table_data):
        for c_idx, val in enumerate(row):
            cell = tbl.cell(r_idx, c_idx)
            cell.text = val
            cell.vertical_anchor = MSO_ANCHOR.MIDDLE
            p = cell.text_frame.paragraphs[0]
            p.alignment = PP_ALIGN.CENTER if c_idx > 0 else PP_ALIGN.LEFT
            
            # Formatting
            if r_idx == 0:
                p.font.bold = True
                p.font.size = Pt(11)
                p.font.color.rgb = ACCENT_GREEN if c_idx == 5 else TEXT_WHITE
                cell.fill.solid()
                cell.fill.fore_color.rgb = CARD_BG
            else:
                p.font.size = Pt(10)
                if c_idx == 5:
                    p.font.bold = True
                    p.font.color.rgb = ACCENT_GREEN
                    cell.fill.solid()
                    cell.fill.fore_color.rgb = RGBColor(16, 40, 35)
                else:
                    p.font.color.rgb = TEXT_LIGHT
                    cell.fill.solid()
                    cell.fill.fore_color.rgb = BG_DARK

    # =========================================================================
    # SLIDE 10: THE ASK & VISION
    # =========================================================================
    s10 = prs.slides.add_slide(blank_layout)
    set_slide_background(s10)
    add_header(s10, "Conclusion & Next Steps", "The Ask: Fueling the Next-Gen Disaster Lifeline",
               "Partner with us to build and deploy the world's most resilient peer-to-peer calling tool.")

    # 3 Final Cards
    c1 = add_card(s10, Inches(0.8), Inches(1.9), Inches(3.7), Inches(4.5), border_col=ACCENT_BLUE)
    t1 = s10.shapes.add_textbox(Inches(1.0), Inches(2.1), Inches(3.3), Inches(4.1))
    tf1 = t1.text_frame
    tf1.word_wrap = True
    p1 = tf1.paragraphs[0]
    p1.text = "WHAT WE ARE SEEKING"
    p1.font.size = Pt(14)
    p1.font.bold = True
    p1.font.color.rgb = ACCENT_BLUE
    p1_b = tf1.add_paragraph()
    p1_b.text = "• Seed Grant / Capital:\nFor a 6-month engineering runway (Android native engineers, audio DSP specialists).\n\n• Testing Device Fleet:\n20+ physical Android test phones spanning low-end to flagship chipsets for radio mesh testing."
    p1_b.font.size = Pt(11)
    p1_b.font.color.rgb = TEXT_LIGHT
    p1_b.space_before = Pt(12)

    c2 = add_card(s10, Inches(4.8), Inches(1.9), Inches(3.7), Inches(4.5), border_col=ACCENT_GREEN)
    t2 = s10.shapes.add_textbox(Inches(5.0), Inches(2.1), Inches(3.3), Inches(4.1))
    tf2 = t2.text_frame
    tf2.word_wrap = True
    p2 = tf2.paragraphs[0]
    p2.text = "PILOT PARTNERSHIPS"
    p2.font.size = Pt(14)
    p2.font.bold = True
    p2.font.color.rgb = ACCENT_GREEN
    p2_b = tf2.add_paragraph()
    p2_b.text = "• Disaster Management Authorities:\nNDMA / SDMAs willing to test Vois during municipal monsoon flood drills.\n\n• Event Management Groups:\nFestival, concert, and marathon organizers seeking zero-cost volunteer communications in saturated crowds."
    p2_b.font.size = Pt(11)
    p2_b.font.color.rgb = TEXT_LIGHT
    p2_b.space_before = Pt(12)

    c3 = add_card(s10, Inches(8.8), Inches(1.9), Inches(3.7), Inches(4.5), border_col=ACCENT_AMBER)
    t3 = s10.shapes.add_textbox(Inches(9.0), Inches(2.1), Inches(3.3), Inches(4.1))
    tf3 = t3.text_frame
    tf3.word_wrap = True
    p3 = tf3.paragraphs[0]
    p3.text = "OUR CORE BELIEF"
    p3.font.size = Pt(14)
    p3.font.bold = True
    p3.font.color.rgb = ACCENT_AMBER
    p3_b = tf3.add_paragraph()
    p3_b.text = "\"Connectivity should not be a luxury that vanishes the moment a flood hits or a tower collapses.\n\nWe are building the fail-safe communication layer for humanity—turning everyday smartphones into an indestructible lifeline.\""
    p3_b.font.size = Pt(12)
    p3_b.font.color.rgb = TEXT_WHITE
    p3_b.space_before = Pt(16)

    # Save presentation
    output_path = "/Users/rishideep/Documents/Rishi_Projects/p2p/P2P_Vois_Pitch_Deck.pptx"
    prs.save(output_path)
    print(f"Presentation saved successfully to: {output_path}")

if __name__ == '__main__':
    create_deck()
