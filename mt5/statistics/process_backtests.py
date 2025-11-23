#!/usr/bin/env python3
"""
Smart Backtest Log Processor
Handles multiple symbols and incremental updates without recomputation
"""

import re
import json
import os
from datetime import datetime
from collections import defaultdict
from pathlib import Path

# Configuration
SCRIPT_DIR = Path(__file__).parent
CACHE_FILE = SCRIPT_DIR / "backtest_cache.json"
LOG_BASE_PATH = Path.home() / ".wine_mt5-2/drive_c/Program Files/MetaTrader 5/MQL5/Logs"

# Allowed timeframes (in display order)
ALLOWED_TIMEFRAMES = ['M1', 'M5', 'M15', 'M30', 'H1']


def load_cache():
    """Load previously processed backtests from cache"""
    if CACHE_FILE.exists():
        with open(CACHE_FILE, 'r') as f:
            return json.load(f)
    return {"processed_logs": {}, "backtests": []}


def save_cache(cache):
    """Save processed backtests to cache"""
    with open(CACHE_FILE, 'w') as f:
        json.dump(cache, f, indent=2)


def get_log_fingerprint(log_path):
    """Get fingerprint of log file (mod time + size)"""
    stat = os.stat(log_path)
    return f"{stat.st_mtime}_{stat.st_size}"


def parse_log_file(log_path):
    """Parse MT5 log file and extract backtests using session prefixes"""
    print(f"📖 Parsing: {log_path.name}")
    
    try:
        with open(log_path, 'r', encoding='utf-16', errors='ignore') as f:
            lines = [line.split('\t')[-1].strip() for line in f if '\t' in line]
    except Exception as e:
        print(f"⚠️  Error reading file: {e}")
        return []
    
    # Group lines by session ID (extract from [SESSION:id] prefix on each line)
    backtest_blocks = {}
    session_pattern = re.compile(r'^\[SESSION:(.+?)\]\s*(.*)$')
    
    for line in lines:
        match = session_pattern.match(line)
        if match:
            session_id = match.group(1)
            line_content = match.group(2)
            
            if session_id not in backtest_blocks:
                backtest_blocks[session_id] = []
            
            backtest_blocks[session_id].append(line_content)
    
    # Fallback: If no session prefixes found, use old method
    if not backtest_blocks:
        print(f"  ⚠️  No session prefixes found, using fallback parsing")
        return parse_log_file_fallback(lines, log_path.name)
    
    # Parse each block
    backtests = []
    for session_id, bt_lines in backtest_blocks.items():
        data = {'log_file': log_path.name, 'session_id': session_id}
        
        for line in bt_lines:
            if "Symbol:" in line:
                m = re.search(r'Symbol: (\w+).*?Timeframe: PERIOD_(\w+)', line)
                if m: data.update({'symbol': m.group(1), 'timeframe': m.group(2)})
            elif "Strategy:" in line:
                m = re.search(r'Strategy: (.+)$', line)
                if m: data['strategy'] = m.group(1).strip()
            elif "Money:" in line and "Risk=" in line and "TP Multiplier=" in line:
                # Extract Risk and TP Multiplier from Money line
                # Format: "Money: Initial=$10000.00 | Risk=1.0% | TP Multiplier=3.0 (RRR 1:3.0)"
                m_risk = re.search(r'Risk=([0-9.]+)%', line)
                m_tp = re.search(r'TP Multiplier=([0-9.]+)', line)
                if m_risk: data['risk_percent'] = float(m_risk.group(1))
                if m_tp: data['tp_multiplier'] = float(m_tp.group(1))
            elif "Trading Hours:" in line:
                # Extract trading hours
                # Format: "Trading Hours: 7:00 - 17:00"
                m = re.search(r'Trading Hours:\s*(\d+):00\s*-\s*(\d+):00', line)
                if m: data['trading_hours'] = f"{m.group(1)}:00-{m.group(2)}:00"
            elif "Initial Deposit:" in line:
                m = re.search(r'\$([0-9,.]+)', line)
                if m: data['initial'] = float(m.group(1).replace(',', ''))
            elif "Current Equity:" in line:
                m = re.search(r'\$([0-9,.]+)', line)
                if m: data['equity'] = float(m.group(1).replace(',', ''))
            elif "Net Profit:" in line:
                m = re.search(r'\$([0-9,.-]+)\s*\(([0-9.-]+)%\)', line)
                if m: 
                    data['profit'] = float(m.group(1).replace(',', ''))
                    data['roi'] = float(m.group(2))
            elif "Total:" in line:
                m = re.search(r'Total: (\d+).*?Active: (\d+)', line)
                if m: 
                    data['total_trades'] = int(m.group(1))
                    data['active'] = int(m.group(2))
            elif "Wins:" in line:
                m = re.search(r'Wins: (\d+).*?Losses: (\d+)', line)
                if m: 
                    data['wins'] = int(m.group(1))
                    data['losses'] = int(m.group(2))
            elif "Win Rate:" in line:
                m = re.search(r'([0-9.]+)%', line)
                if m: data['win_rate'] = float(m.group(1))
            elif "Profit Factor:" in line:
                m = re.search(r'([0-9.]+)$', line)
                if m: data['profit_factor'] = float(m.group(1))
            elif "Pattern: Min" in line:
                m = re.search(r'Min (\d+) bars', line)
                if m: data['pattern_bars'] = int(m.group(1))
            elif "Trend: Spread multiplier" in line:
                m = re.search(r'= ([0-9.]+)', line)
                if m: data['trend_mult'] = float(m.group(1))
        
        if data.get('symbol'):
            backtests.append(data)
    
    print(f"  ✅ Found {len(backtests)} backtests ({len(backtest_blocks)} with session markers)")
    return backtests


def parse_log_file_fallback(lines, log_file_name):
    """Fallback parser for logs without session markers (old format)"""
    markers = [i for i, line in enumerate(lines) if "FIRST COMPUTATION COMPLETE" in line]
    
    backtests = []
    for i in range(len(markers)):
        start = markers[i]
        end = markers[i+1] if i+1 < len(markers) else len(lines)
        section = lines[start:end]
        
        config_start = config_end = None
        for j, line in enumerate(section):
            if "INDICATOR CONFIGURATION" in line:
                config_start = j
            elif config_start and "========================================" in line and j > config_start + 20:
                config_end = j + 1
                break
        
        if config_start and config_end:
            bt_lines = section[config_start:config_end]
            
            data = {'log_file': log_file_name}
            for line in bt_lines:
                if "Symbol:" in line:
                    m = re.search(r'Symbol: (\w+).*?Timeframe: PERIOD_(\w+)', line)
                    if m: data.update({'symbol': m.group(1), 'timeframe': m.group(2)})
                elif "Strategy:" in line:
                    m = re.search(r'Strategy: (.+)$', line)
                    if m: data['strategy'] = m.group(1).strip()
                elif "Money:" in line and "Risk=" in line and "TP Multiplier=" in line:
                    # Extract Risk and TP Multiplier from Money line
                    m_risk = re.search(r'Risk=([0-9.]+)%', line)
                    m_tp = re.search(r'TP Multiplier=([0-9.]+)', line)
                    if m_risk: data['risk_percent'] = float(m_risk.group(1))
                    if m_tp: data['tp_multiplier'] = float(m_tp.group(1))
                elif "Trading Hours:" in line:
                    # Extract trading hours
                    m = re.search(r'Trading Hours:\s*(\d+):00\s*-\s*(\d+):00', line)
                    if m: data['trading_hours'] = f"{m.group(1)}:00-{m.group(2)}:00"
                elif "Initial Deposit:" in line:
                    m = re.search(r'\$([0-9,.]+)', line)
                    if m: data['initial'] = float(m.group(1).replace(',', ''))
                elif "Current Equity:" in line:
                    m = re.search(r'\$([0-9,.]+)', line)
                    if m: data['equity'] = float(m.group(1).replace(',', ''))
                elif "Net Profit:" in line:
                    m = re.search(r'\$([0-9,.-]+)\s*\(([0-9.-]+)%\)', line)
                    if m: 
                        data['profit'] = float(m.group(1).replace(',', ''))
                        data['roi'] = float(m.group(2))
                elif "Total:" in line:
                    m = re.search(r'Total: (\d+).*?Active: (\d+)', line)
                    if m: 
                        data['total_trades'] = int(m.group(1))
                        data['active'] = int(m.group(2))
                elif "Wins:" in line:
                    m = re.search(r'Wins: (\d+).*?Losses: (\d+)', line)
                    if m: 
                        data['wins'] = int(m.group(1))
                        data['losses'] = int(m.group(2))
                elif "Win Rate:" in line:
                    m = re.search(r'([0-9.]+)%', line)
                    if m: data['win_rate'] = float(m.group(1))
                elif "Profit Factor:" in line:
                    m = re.search(r'([0-9.]+)$', line)
                    if m: data['profit_factor'] = float(m.group(1))
                elif "Pattern: Min" in line:
                    m = re.search(r'Min (\d+) bars', line)
                    if m: data['pattern_bars'] = int(m.group(1))
                elif "Trend: Spread multiplier" in line:
                    m = re.search(r'= ([0-9.]+)', line)
                    if m: data['trend_mult'] = float(m.group(1))
            
            if data.get('symbol'):
                backtests.append(data)
    
    return backtests


def aggregate_by_config(backtests):
    """Aggregate backtests by configuration AND symbol"""
    configs = defaultdict(list)
    
    for bt in backtests:
        key = (
            bt.get('symbol', 'N/A'),
            bt.get('trend_mult', 4.0),           # Spread multiplier
            bt.get('tp_multiplier', 2.0),        # TP Profit Multiplier
            bt.get('trading_hours', '0:00-24:00'), # Trading hours
            bt.get('strategy', 'N/A')            # Strategy
        )
        configs[key].append(bt)
    
    aggregates = []
    for config_key, tests in configs.items():
        symbol, trend_mult, tp_multiplier, trading_hours, strategy = config_key
        
        total_tests = len(tests)
        avg_roi = sum(t.get('roi', 0) for t in tests) / total_tests if total_tests else 0
        avg_win_rate = sum(t.get('win_rate', 0) for t in tests) / total_tests if total_tests else 0
        avg_profit_factor = sum(t.get('profit_factor', 0) for t in tests) / total_tests if total_tests else 0
        total_trades = sum(t.get('total_trades', 0) for t in tests)
        total_wins = sum(t.get('wins', 0) for t in tests)
        total_losses = sum(t.get('losses', 0) for t in tests)
        total_profit = sum(t.get('profit', 0) for t in tests)
        
        # Get timeframes (only allowed ones, in proper order)
        timeframes = sorted(set(t.get('timeframe', 'N/A') for t in tests), 
                           key=lambda x: ALLOWED_TIMEFRAMES.index(x) if x in ALLOWED_TIMEFRAMES else 99)
        
        # Best/worst timeframes
        best_tf = max(tests, key=lambda x: x.get('roi', 0))
        worst_tf = min(tests, key=lambda x: x.get('roi', 0))
        
        aggregates.append({
            'symbol': symbol,
            'trend_mult': trend_mult,
            'tp_multiplier': tp_multiplier,
            'trading_hours': trading_hours,
            'strategy': strategy,
            'total_tests': total_tests,
            'timeframes': timeframes,
            'avg_roi': avg_roi,
            'avg_win_rate': avg_win_rate,
            'avg_profit_factor': avg_profit_factor,
            'total_trades': total_trades,
            'total_wins': total_wins,
            'total_losses': total_losses,
            'total_profit': total_profit,
            'best_tf': best_tf.get('timeframe', 'N/A'),
            'best_roi': best_tf.get('roi', 0.0),
            'worst_tf': worst_tf.get('timeframe', 'N/A'),
            'worst_roi': worst_tf.get('roi', 0.0),
            'backtests': tests  # Store the actual backtest data for this config
        })
    
    # Calculate quality score for each configuration (penalize negative worst TFs)
    for agg in aggregates:
        base_score = agg['avg_profit_factor']
        worst_roi = agg['worst_roi']
        
        # Apply penalties based on worst timeframe performance
        if worst_roi < -20:  # Very bad worst TF (-20% or worse)
            penalty = 0.3  # Severe penalty: only 30% of PF counts
        elif worst_roi < -10:  # Bad worst TF (-10% to -20%)
            penalty = 0.5  # Heavy penalty: only 50% of PF counts
        elif worst_roi < 0:  # Any negative TF (0% to -10%)
            penalty = 0.7  # Moderate penalty: only 70% of PF counts
        else:  # All timeframes positive
            penalty = 1.0  # No penalty
        
        # Additional penalty for suspiciously low ROI with high PF
        if agg['avg_roi'] < 5 and base_score > 1.5:
            penalty *= 0.8  # Inconsistency penalty
        
        agg['quality_score'] = base_score * penalty
    
    return sorted(aggregates, key=lambda x: x['quality_score'], reverse=True)


def generate_summary(aggregates, all_backtests):
    """Generate HTML summary file"""
    ts = datetime.now().strftime("%Y%m%d%H%M")
    
    # Count symbols
    symbols = set(bt.get('symbol') for bt in all_backtests)
    
    # HTML with tabs
    html_file = SCRIPT_DIR / f"config_summary_{ts}.html"
    
    # Group aggregates by symbol for tabs
    symbols_list = sorted(symbols)
    symbol_aggregates = {}
    for symbol in symbols_list:
        symbol_aggregates[symbol] = [agg for agg in aggregates if agg['symbol'] == symbol]
    
    with open(html_file, 'w', encoding='utf-8') as f:
        f.write(f'''<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Configuration Summary</title>
<style>
body{{font-family:Arial,sans-serif;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);padding:20px;margin:0}}
.container{{max-width:1400px;margin:0 auto;background:white;border-radius:12px;padding:30px;box-shadow:0 10px 40px rgba(0,0,0,0.3)}}
h1{{text-align:center;color:#2c3e50;margin-bottom:10px;font-size:2.5em}}
.meta{{text-align:center;color:#7f8c8d;margin-bottom:30px;font-size:1.1em}}
.summary-grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:20px;margin:30px 0}}
.summary-card{{background:linear-gradient(135deg,#667eea,#764ba2);color:white;padding:20px;border-radius:10px;text-align:center}}
.summary-card .label{{font-size:0.9em;opacity:0.9;margin-bottom:10px}}
.summary-card .value{{font-size:2.2em;font-weight:bold}}

/* Tabs */
.tabs{{display:flex;justify-content:center;gap:10px;margin:40px 0 20px 0;flex-wrap:wrap}}
.tab-button{{background:#ecf0f1;color:#2c3e50;border:none;padding:15px 30px;font-size:1.1em;font-weight:bold;border-radius:10px 10px 0 0;cursor:pointer;transition:all 0.3s;border-bottom:4px solid transparent}}
.tab-button:hover{{transform:translateY(-2px);filter:brightness(0.95)}}
.tab-button.active{{background:linear-gradient(135deg,#667eea,#764ba2);color:white;border-bottom:4px solid #2c3e50}}
.tab-excellent{{background:#90ee90;color:#155724}}
.tab-good{{background:#fff3cd;color:#856404}}
.tab-neutral{{background:#e2e3e5;color:#383d41}}
.tab-poor{{background:#f8d7da;color:#721c24}}
.tab-content{{display:none;animation:fadeIn 0.5s}}
.tab-content.active{{display:block}}
@keyframes fadeIn{{from{{opacity:0}}to{{opacity:1}}}}

.config{{background:#f8f9fa;margin:20px 0;border-radius:12px;overflow:hidden;box-shadow:0 4px 8px rgba(0,0,0,0.1);transition:transform 0.3s}}
.config:hover{{transform:translateY(-5px)}}
.config-header{{background:linear-gradient(135deg,#667eea,#764ba2);color:white;padding:20px}}
.config-header h2{{margin:0 0 10px 0}}
.config-body{{padding:25px}}
.stats-row{{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:15px;margin:15px 0}}
.stat-box{{background:white;padding:15px;border-radius:8px;border-left:4px solid #3498db;box-shadow:0 2px 4px rgba(0,0,0,0.05)}}
.stat-label{{font-weight:600;color:#7f8c8d;font-size:0.85em;text-transform:uppercase;letter-spacing:0.5px}}
.stat-value{{font-size:1.4em;color:#2c3e50;font-weight:bold;margin-top:5px}}
.section-title{{font-weight:bold;color:#2c3e50;font-size:1.1em;margin:20px 0 10px 0;padding:10px;background:#ecf0f1;border-radius:5px;border-left:5px solid #3498db}}
.medal{{font-size:2em;margin-right:10px}}
.pos{{color:#27ae60}}
.neg{{color:#e74c3c}}
.badge{{display:inline-block;padding:5px 12px;border-radius:15px;font-size:0.85em;font-weight:bold;margin:0 5px}}
.badge-excellent{{background:#27ae60;color:white}}
.badge-good{{background:#3498db;color:white}}
.badge-poor{{background:#e74c3c;color:white}}

/* Overview table */
.overview-section{{background:#f8f9fa;border-radius:15px;padding:30px;margin:30px 0;box-shadow:0 2px 8px rgba(0,0,0,0.08)}}
.overview-table{{width:100%;border-collapse:separate;border-spacing:0 10px;margin:20px 0}}
.overview-row{{background:white;border-radius:10px;overflow:hidden;transition:all 0.3s;cursor:pointer;box-shadow:0 2px 4px rgba(0,0,0,0.05)}}
.overview-row:hover{{transform:scale(1.02);box-shadow:0 6px 16px rgba(102,126,234,0.25)}}
.overview-row td{{padding:20px;border:none}}
.overview-rank{{font-size:1.5em;font-weight:bold;color:#667eea;width:60px;text-align:center}}
.overview-symbol{{font-size:1.3em;font-weight:bold;color:#2c3e50;width:150px}}
.overview-status{{font-size:1.2em;width:100px;text-align:center}}
.overview-configs{{color:#7f8c8d;font-size:0.95em}}
.overview-metrics{{text-align:right}}
.overview-metric{{display:inline-block;margin:0 15px}}
.overview-metric-label{{font-size:0.85em;color:#7f8c8d;display:block}}
.overview-metric-value{{font-size:1.3em;font-weight:bold;color:#2c3e50}}
</style>
<script>
function showTab(symbol) {{
    // Hide all tabs
    var tabs = document.getElementsByClassName('tab-content');
    for (var i = 0; i < tabs.length; i++) {{
        tabs[i].classList.remove('active');
    }}
    
    // Remove active from all buttons
    var buttons = document.getElementsByClassName('tab-button');
    for (var i = 0; i < buttons.length; i++) {{
        buttons[i].classList.remove('active');
    }}
    
    // Show selected tab
    document.getElementById('tab-' + symbol).classList.add('active');
    document.getElementById('btn-' + symbol).classList.add('active');
    
    // Scroll to tabs section smoothly
    var tabsSection = document.querySelector('.tabs');
    if (tabsSection) {{
        tabsSection.scrollIntoView({{ behavior: 'smooth', block: 'start' }});
    }}
}}
</script>
</head><body>
<div class="container">
<h1>🏆 Configuration Performance Summary</h1>
<div class="meta">
<p>Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
<p>Symbols: {', '.join(sorted(symbols))} | {len(aggregates)} Configurations | {len(all_backtests)} Backtests</p>
</div>

<div class="summary-grid">
<div class="summary-card">
<div class="label">Symbols</div>
<div class="value">{len(symbols)}</div>
</div>
<div class="summary-card">
<div class="label">Configurations</div>
<div class="value">{len(aggregates)}</div>
</div>
<div class="summary-card">
<div class="label">Total Tests</div>
<div class="value">{len(all_backtests)}</div>
</div>
<div class="summary-card">
<div class="label">Best Profit Factor</div>
<div class="value">{aggregates[0]['avg_profit_factor']:.2f}</div>
</div>
<div class="summary-card">
<div class="label">Total Trades</div>
<div class="value">{sum(a['total_trades'] for a in aggregates):,}</div>
</div>
</div>

<h2 style="text-align:center;color:#2c3e50;margin:40px 0 20px 0">📊 Configuration Rankings by Symbol</h2>

<!-- Overview Section (Always Visible) -->
<div class="overview-section">
<h3 style="text-align:center;color:#2c3e50;margin:0 0 10px 0">🏆 Symbol Performance Rankings</h3>
<p style="text-align:center;color:#7f8c8d;margin-bottom:20px">
Ranked by <strong>Quality Score</strong> (PF adjusted for negative timeframes) • Click any symbol for details
</p>
''')
        
        # Calculate symbol-level metrics for ranking and generate overview table
        symbol_rankings = []
        for symbol in symbols_list:
            symbol_configs = symbol_aggregates[symbol]
            positive_configs = sum(1 for cfg in symbol_configs if cfg['avg_profit_factor'] > 1.0)
            total_configs = len(symbol_configs)
            positive_percent = (positive_configs / total_configs * 100) if total_configs > 0 else 0
            has_negative_tf = any(cfg['worst_roi'] < 0 for cfg in symbol_configs)
            
            # Calculate average metrics across all configs
            avg_pf = sum(cfg['avg_profit_factor'] for cfg in symbol_configs) / total_configs if total_configs else 0
            avg_roi = sum(cfg['avg_roi'] for cfg in symbol_configs) / total_configs if total_configs else 0
            avg_wr = sum(cfg['avg_win_rate'] for cfg in symbol_configs) / total_configs if total_configs else 0
            total_trades_all = sum(cfg['total_trades'] for cfg in symbol_configs)
            
            # Determine emoji
            if positive_percent == 100 and not has_negative_tf:
                emoji = '🟢'
            elif positive_percent >= 66:
                emoji = '🟡'
            elif positive_percent >= 33:
                emoji = '⚪'
            else:
                emoji = '🔴'
            
            symbol_rankings.append({
                'symbol': symbol,
                'emoji': emoji,
                'avg_pf': avg_pf,
                'avg_roi': avg_roi,
                'avg_wr': avg_wr,
                'positive_configs': positive_configs,
                'total_configs': total_configs,
                'total_trades': total_trades_all
            })
        
        # Calculate quality score for each symbol (penalize negative worst TFs)
        for sym_data in symbol_rankings:
            symbol_configs = symbol_aggregates[sym_data['symbol']]
            
            # Check for negative worst timeframes
            min_worst_roi = min(cfg['worst_roi'] for cfg in symbol_configs)
            
            # Base score is average PF
            base_score = sym_data['avg_pf']
            
            # Apply penalties
            if min_worst_roi < -20:  # Very bad worst TF
                penalty = 0.3  # Severe penalty
            elif min_worst_roi < -10:  # Bad worst TF
                penalty = 0.5
            elif min_worst_roi < 0:  # Any negative TF
                penalty = 0.7
            else:  # All timeframes positive
                penalty = 1.0  # No penalty
            
            # Additional penalty for low ROI (if PF is good but ROI is low = inconsistency)
            if sym_data['avg_roi'] < 5 and base_score > 1.5:
                penalty *= 0.8  # Something is wrong
            
            sym_data['quality_score'] = base_score * penalty
        
        # Sort by quality score (PF adjusted for negative timeframes)
        symbol_rankings.sort(key=lambda x: x['quality_score'], reverse=True)
        
        # Create overview table
        f.write('<table class="overview-table">\n')
        for rank, sym_data in enumerate(symbol_rankings, 1):
            medal = '🥇' if rank == 1 else '🥈' if rank == 2 else '🥉' if rank == 3 else f'#{rank}'
            
            quality_score = sym_data.get('quality_score', sym_data['avg_pf'])
            f.write(f'''<tr class="overview-row" onclick="showTab('{sym_data['symbol']}')">
<td class="overview-rank">{medal}</td>
<td class="overview-symbol">{sym_data['symbol']} {sym_data['emoji']}</td>
<td class="overview-configs">{sym_data['positive_configs']}/{sym_data['total_configs']} configs<br>{sym_data['total_trades']:,} trades</td>
<td class="overview-metrics">
<div class="overview-metric">
<span class="overview-metric-label">Quality</span>
<span class="overview-metric-value ''' + ('pos' if quality_score > 1.0 else 'neg') + f'''">{quality_score:.2f}</span>
</div>
<div class="overview-metric">
<span class="overview-metric-label">PF</span>
<span class="overview-metric-value ''' + ('pos' if sym_data['avg_pf'] > 1.0 else 'neg') + f'''">{sym_data['avg_pf']:.2f}</span>
</div>
<div class="overview-metric">
<span class="overview-metric-label">ROI</span>
<span class="overview-metric-value ''' + ('pos' if sym_data['avg_roi'] > 0 else 'neg') + f'''">{sym_data['avg_roi']:.1f}%</span>
</div>
<div class="overview-metric">
<span class="overview-metric-label">WR</span>
<span class="overview-metric-value">{sym_data['avg_wr']:.1f}%</span>
</div>
</td>
</tr>
''')
        
        f.write('</table>\n')
        f.write('</div>\n\n')
        
        # Symbol detail tabs heading
        f.write('<h3 style="text-align:center;color:#2c3e50;margin:40px 0 20px 0">📋 Detailed Configuration Views</h3>\n\n')
        
        # Tab Buttons for individual symbols
        f.write('<div class="tabs">\n')
        
        # Generate tab buttons with performance color coding
        for i, symbol in enumerate(symbols_list):
            active_class = 'active' if i == 0 else ''
            
            # Calculate performance for this symbol (% of configs with profit factor > 1.0)
            symbol_configs = symbol_aggregates[symbol]
            positive_configs = sum(1 for cfg in symbol_configs if cfg['avg_profit_factor'] > 1.0)
            total_configs = len(symbol_configs)
            positive_percent = (positive_configs / total_configs * 100) if total_configs > 0 else 0
            
            # Smart negative TF check: Allow minor outliers
            has_negative_tf = any(cfg['worst_roi'] < 0 for cfg in symbol_configs)
            can_be_green = True
            
            if has_negative_tf:
                # Check if negative TFs are minor outliers (can still be green)
                for cfg in symbol_configs:
                    if cfg['worst_roi'] < 0:
                        # Get all positive TF ROIs for this config (from stored backtests)
                        # We need to check if this negative is insignificant
                        all_tests = cfg.get('backtests', [])
                        
                        if len(all_tests) >= 3:  # Need at least 3 TFs to judge outliers
                            positive_rois = [t.get('roi', 0) for t in all_tests if t.get('roi', 0) > 0]
                            negative_count = sum(1 for t in all_tests if t.get('roi', 0) < 0)
                            
                            if positive_rois and len(positive_rois) >= 2:
                                # Calculate median of positive TFs
                                positive_rois_sorted = sorted(positive_rois)
                                median_positive = positive_rois_sorted[len(positive_rois_sorted) // 2]
                                
                                # Check if negative is minor (< 10% of positive median) and minority
                                threshold = median_positive * 0.1
                                is_minor = cfg['worst_roi'] > -threshold  # e.g., -5% when median is +100%
                                is_minority = negative_count <= (len(all_tests) / 3)  # Max 33% can be negative
                                
                                if not (is_minor and is_minority):
                                    can_be_green = False
                                    break
                            else:
                                can_be_green = False
                                break
                        else:
                            # Not enough data to judge, be conservative
                            can_be_green = False
                            break
            
            # Determine color class and emoji based on performance
            # Green if 100% positive PF AND (no negative TFs OR minor outliers allowed)
            if positive_percent == 100 and can_be_green:
                color_class = 'tab-excellent'  # All positive (light green)
                emoji = '🟢'
            elif positive_percent >= 66:
                color_class = 'tab-good'        # Mostly positive (light yellow)
                emoji = '🟡'
            elif positive_percent >= 33:
                color_class = 'tab-neutral'     # Minor positive (gray)
                emoji = '⚪'
            else:
                color_class = 'tab-poor'        # No/few positive (light red)
                emoji = '🔴'
            
            # Format: "SYMBOL 🟢 (3/3)" or "SYMBOL 🟡 (2/3)"
            label = f'{symbol} {emoji} ({positive_configs}/{total_configs})'
            f.write(f'<button class="tab-button {active_class} {color_class}" id="btn-{symbol}" onclick="showTab(\'{symbol}\')">{label}</button>\n')
        
        f.write('</div>\n\n')
        
        # Generate tab content for each symbol
        for i, symbol in enumerate(symbols_list):
            active_class = 'active' if i == 0 else ''
            symbol_configs = symbol_aggregates[symbol]
            
            f.write(f'<div class="tab-content {active_class}" id="tab-{symbol}">\n')
            f.write(f'<h3 style="text-align:center;color:#2c3e50;margin:20px 0">🎯 {symbol} - Top {len(symbol_configs)} Configuration(s)</h3>\n')
            
            # Generate configs for this symbol
            for rank, agg in enumerate(symbol_configs, 1):
                if rank == 1:
                    medal, badge_class = '🥇', 'badge-excellent'
                elif rank == 2:
                    medal, badge_class = '🥈', 'badge-excellent'
                elif rank == 3:
                    medal, badge_class = '🥉', 'badge-good'
                else:
                    medal = f'#{rank}'
                    badge_class = 'badge-good' if agg['avg_profit_factor'] > 1.0 else 'badge-poor'
                
                # Build the config HTML
                tf_list = ', '.join(ALLOWED_TIMEFRAMES)
                quality_note = f'<span style="color:#e74c3c"> ⚠️ Worst TF is negative: {agg["worst_roi"]:.1f}% penalty applied!</span>' if agg['worst_roi'] < 0 else '<span style="color:#27ae60"> ✅ All timeframes positive!</span>'
                
                f.write(f'''
<div class="config">
<div class="config-header">
<h2><span class="medal">{medal}</span> Configuration #{rank}
<span class="badge {badge_class}">PF: {agg['avg_profit_factor']:.2f}</span>
<span class="badge badge-good">Quality: {agg.get('quality_score', agg['avg_profit_factor']):.2f}</span>
</h2>
<div style="font-size:0.95em;opacity:0.95">
Spread: {agg['trend_mult']}x | TP: {agg['tp_multiplier']}x | Hours: {agg['trading_hours']}
<br>{agg['strategy']}
<br>Timeframes: {', '.join(agg['timeframes'])} ({agg['total_tests']} tests)
</div>
</div>
<div class="config-body">

<div class="section-title">⚡ Performance Metrics</div>
<div class="stats-row">
<div class="stat-box">
<div class="stat-label">Average ROI</div>
<div class="stat-value ''' + ('pos' if agg['avg_roi'] > 0 else 'neg') + f'''">{agg['avg_roi']:.2f}%</div>
</div>
<div class="stat-box">
<div class="stat-label">Average Win Rate</div>
<div class="stat-value">{agg['avg_win_rate']:.2f}%</div>
</div>
<div class="stat-box">
<div class="stat-label">Profit Factor</div>
<div class="stat-value">{agg['avg_profit_factor']:.2f}</div>
</div>
<div class="stat-box">
<div class="stat-label">Combined Profit</div>
<div class="stat-value ''' + ('pos' if agg['total_profit'] > 0 else 'neg') + f'''">${agg['total_profit']:,.0f}</div>
</div>
</div>

<div class="section-title">📈 Trade Statistics</div>
<div class="stats-row">
<div class="stat-box">
<div class="stat-label">Total Trades</div>
<div class="stat-value">{agg['total_trades']:,}</div>
</div>
<div class="stat-box">
<div class="stat-label">Wins / Losses</div>
<div class="stat-value"><span class="pos">{agg['total_wins']:,}</span> / <span class="neg">{agg['total_losses']:,}</span></div>
</div>
<div class="stat-box">
<div class="stat-label">Overall Win Rate</div>
<div class="stat-value">{(agg['total_wins']/agg['total_trades']*100 if agg['total_trades'] else 0):.2f}%</div>
</div>
</div>

<div class="section-title">📊 Timeframe Performance Ranking</div>
''')
                
                # Get all timeframe results for this configuration (from stored backtests)
                tf_results = []
                for bt in agg.get('backtests', []):
                    if bt.get('timeframe') in ALLOWED_TIMEFRAMES:
                        tf_results.append({
                            'tf': bt.get('timeframe'),
                            'roi': bt.get('roi', 0),
                            'pf': bt.get('profit_factor', 0),
                            'wr': bt.get('win_rate', 0),
                            'trades': bt.get('total_trades', 0),
                            'wins': bt.get('wins', 0),
                            'losses': bt.get('losses', 0),
                            'profit': bt.get('profit', 0)
                        })
                
                # Sort by ROI descending
                tf_results.sort(key=lambda x: x['roi'], reverse=True)
                
                # Display ranked timeframes
                f.write('<div style="margin:15px 0">\n')
                
                if not tf_results:
                    # Fallback message if no data found
                    f.write('<div style="padding:20px;text-align:center;color:#7f8c8d;background:#ecf0f1;border-radius:8px">⚠️ No timeframe data available for this configuration</div>\n')
                
                for tf_rank, tf_data in enumerate(tf_results, 1):
                    if tf_rank == 1:
                        rank_emoji = '🥇'
                        rank_color = '#27ae60'
                    elif tf_rank == 2:
                        rank_emoji = '🥈'
                        rank_color = '#3498db'
                    elif tf_rank == 3:
                        rank_emoji = '🥉'
                        rank_color = '#e67e22'
                    else:
                        rank_emoji = f'#{tf_rank}'
                        rank_color = '#7f8c8d'
                    
                    roi_color = '#27ae60' if tf_data['roi'] >= 0 else '#e74c3c'
                    pf_color = '#27ae60' if tf_data['pf'] > 1.0 else '#e74c3c'
                    profit_color = '#27ae60' if tf_data['profit'] >= 0 else '#e74c3c'
                    
                    f.write(f'''
<div style="background:white;padding:15px;margin:8px 0;border-radius:8px;border-left:4px solid {rank_color};display:flex;align-items:center;justify-content:space-between;box-shadow:0 2px 4px rgba(0,0,0,0.05)">
<div style="flex:0 0 60px;font-size:1.5em;font-weight:bold;color:{rank_color};text-align:center">{rank_emoji}</div>
<div style="flex:0 0 80px;font-size:1.3em;font-weight:bold;color:#2c3e50">{tf_data['tf']}</div>
<div style="flex:1;display:flex;gap:15px;justify-content:space-around">
<div style="text-align:center">
<div style="font-size:0.75em;color:#7f8c8d;text-transform:uppercase">Profit</div>
<div style="font-size:1.1em;font-weight:bold;color:{profit_color}">${tf_data['profit']:,.0f}</div>
</div>
<div style="text-align:center">
<div style="font-size:0.75em;color:#7f8c8d;text-transform:uppercase">ROI</div>
<div style="font-size:1.2em;font-weight:bold;color:{roi_color}">{tf_data['roi']:.1f}%</div>
</div>
<div style="text-align:center">
<div style="font-size:0.75em;color:#7f8c8d;text-transform:uppercase">PF</div>
<div style="font-size:1.2em;font-weight:bold;color:{pf_color}">{tf_data['pf']:.2f}</div>
</div>
<div style="text-align:center">
<div style="font-size:0.75em;color:#7f8c8d;text-transform:uppercase">WR</div>
<div style="font-size:1.2em;font-weight:bold;color:#2c3e50">{tf_data['wr']:.1f}%</div>
</div>
<div style="text-align:center">
<div style="font-size:0.75em;color:#7f8c8d;text-transform:uppercase">Trades</div>
<div style="font-size:1.2em;font-weight:bold;color:#2c3e50">{tf_data['trades']}</div>
</div>
<div style="text-align:center">
<div style="font-size:0.75em;color:#7f8c8d;text-transform:uppercase">W/L</div>
<div style="font-size:1.0em;color:#2c3e50"><span style="color:#27ae60">{tf_data['wins']}</span>/<span style="color:#e74c3c">{tf_data['losses']}</span></div>
</div>
</div>
</div>
''')
                
                f.write('</div>\n')
                
                f.write('''
<div style="margin-top:15px;padding:12px;background:#ecf0f1;border-radius:5px;font-size:0.9em;color:#7f8c8d">
<strong>📊 Quality Score:</strong> PF adjusted for timeframe consistency. Negative worst TF = penalty.
<br>{quality_note}
<br><strong>🟢 Green Tab Criteria:</strong> All positive OR minor outlier (≤33% negative TFs, each &lt;10% of positive median)
<br><strong>⏱️ Timeframes:</strong> Analysis limited to {tf_list} (others excluded)
</div>

</div>
</div>
''')
            
            f.write('</div>\n')  # Close tab-content
        
        f.write('</div></body></html>')
    
    print(f"✅ HTML: {html_file.name}")
    return html_file


def main():
    """Main processing function"""
    print("=" * 80)
    print("🚀 Smart Backtest Log Processor")
    print("=" * 80)
    
    # Load cache
    cache = load_cache()
    print(f"📦 Loaded cache: {len(cache['backtests'])} existing backtests")
    
    # Find log files
    if not LOG_BASE_PATH.exists():
        print(f"⚠️  Log directory not found: {LOG_BASE_PATH}")
        return
    
    log_files = sorted(LOG_BASE_PATH.glob("*.log"))
    print(f"📁 Found {len(log_files)} log files")
    
    # Process new/changed logs
    new_backtests = []
    for log_file in log_files:
        fingerprint = get_log_fingerprint(log_file)
        
        if log_file.name in cache['processed_logs'] and cache['processed_logs'][log_file.name] == fingerprint:
            print(f"⏭️  Skipping {log_file.name} (already processed)")
            continue
        
        # Parse new/changed file
        backtests = parse_log_file(log_file)
        new_backtests.extend(backtests)
        
        # Update cache
        cache['processed_logs'][log_file.name] = fingerprint
    
    # Combine with cached backtests
    all_backtests = cache['backtests'] + new_backtests
    
    # Remove duplicates based on comprehensive key (keep latest occurrence)
    backtest_dict = {}
    
    for bt in all_backtests:
        # Create comprehensive key including configuration parameters:
        # - Spread multiplier (TrendSpreadMultiplier)
        # - TP Profit Multiplier
        # - Trading hours
        # - Strategy
        key = (
            bt.get('symbol'),
            bt.get('timeframe'),
            bt.get('trend_mult'),            # Spread multiplier
            bt.get('tp_multiplier'),         # TP Profit Multiplier
            bt.get('trading_hours'),         # Trading hours
            bt.get('strategy'),              # Strategy
        )
        
        # Store backtest with this key (later occurrences overwrite earlier ones)
        backtest_dict[key] = bt
    
    # Convert back to list
    unique_backtests = list(backtest_dict.values())
    duplicates_removed = len(all_backtests) - len(unique_backtests)
    
    # Filter to only allowed timeframes
    filtered_backtests = [bt for bt in unique_backtests if bt.get('timeframe') in ALLOWED_TIMEFRAMES]
    timeframes_removed = len(unique_backtests) - len(filtered_backtests)
    
    print(f"\n📊 Total backtests: {len(filtered_backtests)} ({len(new_backtests)} new)")
    if duplicates_removed > 0:
        print(f"   🗑️  Removed {duplicates_removed} duplicate test(s)")
    if timeframes_removed > 0:
        print(f"   🗑️  Filtered out {timeframes_removed} non-standard timeframe(s) (keeping only: {', '.join(ALLOWED_TIMEFRAMES)})")
    
    if len(filtered_backtests) == 0:
        print("⚠️  No backtests found!")
        return
    
    # Use filtered backtests from now on
    unique_backtests = filtered_backtests
    
    # Save updated cache
    cache['backtests'] = unique_backtests
    save_cache(cache)
    print(f"💾 Cache updated")
    
    # Generate aggregates
    print(f"\n📈 Aggregating by configuration...")
    aggregates = aggregate_by_config(unique_backtests)
    print(f"   Found {len(aggregates)} unique configurations")
    
    # Generate summary file
    print(f"\n📝 Generating summary file...")
    html_file = generate_summary(aggregates, unique_backtests)
    
    # Display top configs
    print(f"\n🏆 TOP 10 CONFIGURATIONS BY QUALITY SCORE (PF with penalties):")
    for i, agg in enumerate(aggregates[:10], 1):
        quality = agg.get('quality_score', agg['avg_profit_factor'])
        print(f"  {i}. {agg['symbol']}: Spread {agg['trend_mult']}x, TP {agg['tp_multiplier']}x, Hours {agg['trading_hours']}")
        print(f"     Strategy: {agg['strategy']}")
        print(f"     Quality Score: {quality:.2f} | PF: {agg['avg_profit_factor']:.2f} | ROI: {agg['avg_roi']:.2f}% | Worst TF: {agg['worst_roi']:.1f}%")
        print(f"     Timeframes: {', '.join(agg['timeframes'])}")
    
    print(f"\n✅ Done!")


if __name__ == "__main__":
    main()

