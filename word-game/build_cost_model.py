"""构建 AI 陪玩成本模型工作簿（参数可调、公式联动）。"""
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill, Border, Side
from openpyxl.utils import get_column_letter

OUT = "/Users/liqinkai/Programs/fordsh/word-game/ai-companion-cost.xlsx"

BOLD = Font(bold=True)
HEAD = Font(bold=True, color="FFFFFF")
HEAD_FILL = PatternFill("solid", fgColor="4472C4")
INPUT_FILL = PatternFill("solid", fgColor="FFF2CC")
DERIVED_FILL = PatternFill("solid", fgColor="E2EFDA")
THIN = Side(style="thin", color="BFBFBF")
BOX = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)

P = "参数假设"
def REF(cell):
    return f"'{P}'!${cell}"

wb = Workbook()

# ---------------- Sheet 1: 参数假设 ----------------
ws = wb.active
ws.title = P
ws["A1"] = "AI 陪玩成本模型 · 参数假设（黄色格可改，其余自动联动）"
ws["A1"].font = Font(bold=True, size=13)
ws["A2"] = "所有单价均为量级估算，签合同前请替换为真实报价"
ws["A2"].font = Font(italic=True, size=10, color="C00000")

rows = [
    ("DAU（日活跃人数）", 10000, "人", "对局发起人数，非注册用户"),
    ("人均每日局数", 5, "局/人/天", "猜词类一局 3 分钟，5 局偏乐观"),
    ("单局轮次", 5, "轮", "实测：无约束 2 轮，抽象约束 5 轮"),
    ("单局 AI 席位数", 3, "席", "真人 1 席 + AI 3 席"),
    ("每席每轮输入 token", 200, "token", "规则+历史，全透明模式下很短"),
    ("每席每轮输出 token", 5, "token", "只吐一个词"),
    ("记忆/上下文膨胀倍数", 1, "倍", "做长期人设记忆时调到 4~8"),
    ("API 输入单价", 0.5, "¥/百万token", "flash 档量级，占位值"),
    ("API 输出单价", 2.0, "¥/百万token", "flash 档量级，占位值"),
    ("自建：单卡月租", 1600, "¥/月", "4090 包月，国内 1200~2000"),
    ("自建：预填充吞吐", 4000, "token/s", "7B Q4 + vLLM 量级"),
    ("自建：解码吞吐", 1500, "token/s", "同上，已按批处理摊薄"),
    ("自建：GPU 利用率", 0.30, "比例", "交互流量集中在晚间，闲置是常态"),
    ("固定成本（人力/云杂项）", 0, "¥/月", "设 0 只比可变成本；要算全成本填 3000"),
    ("付费转化率", 0.03, "比例", "免费用户转会员比例"),
    ("会员月费", 9.9, "¥/月", "不限局订阅"),
]
ws.append([])
ws.append(["参数", "数值", "单位", "说明"])
for c in ws[4]:
    c.font = HEAD
    c.fill = HEAD_FILL
for i, (name, val, unit, note) in enumerate(rows):
    r = 5 + i
    ws.cell(row=r, column=1, value=name)
    c = ws.cell(row=r, column=2, value=val)
    c.fill = INPUT_FILL
    c.border = BOX
    if isinstance(val, float) and val < 1:
        c.number_format = "0.00"
    ws.cell(row=r, column=3, value=unit)
    ws.cell(row=r, column=4, value=note)

ws.column_dimensions["A"].width = 27
ws.column_dimensions["B"].width = 12
ws.column_dimensions["C"].width = 14
ws.column_dimensions["D"].width = 46
ws.freeze_panes = "A5"

# 派生量：行 22 标题，23 表头，24~27 数据
ws["A22"] = "派生量（自动计算，供其他表引用）"
ws["A22"].font = BOLD
ws.append([])
ws.append(["派生量", "数值"])
for c in ws[23]:
    c.font = HEAD
    c.fill = HEAD_FILL
derived = [
    ("每局输入 token", "=B7*B8*B9*B11", "0"),
    ("每局输出 token", "=B7*B8*B10*B11", "0"),
    ("单局 API 成本（¥）", "=B24/1000000*B12+B25/1000000*B13", "0.0000"),
    ("单局 GPU 占用（秒）", "=B24/B15+B25/B16", "0.000"),
]
for i, (name, formula, fmt) in enumerate(derived):
    r = 24 + i
    ws.cell(row=r, column=1, value=name)
    c = ws.cell(row=r, column=2, value=formula)
    c.fill = DERIVED_FILL
    c.border = BOX
    c.number_format = fmt

COST_GAME = REF("B26")   # 单局 API 成本
GPU_SEC = REF("B27")     # 单局 GPU 秒
DAU = REF("B5")
GAMES_PP = REF("B6")
GPU_RENT = REF("B14")
UTIL = REF("B17")
FIXED = REF("B18")
CONV = REF("B19")
PRICE = REF("B20")

# ---------------- Sheet 2: 规模对比 ----------------
ws2 = wb.create_sheet("规模对比")
ws2["A1"] = "不同 DAU 下：API 调用 vs 自建小模型"
ws2["A1"].font = Font(bold=True, size=13)
ws2["A2"] = "自建成本 = 所需常驻 GPU × 月租 + 固定成本；GPU 台数按容量向上取整，至少 1 台"
ws2["A2"].font = Font(italic=True, size=10)

hdr = ["DAU", "日局数", "月局数", "月 API 成本(¥)", "所需 GPU", "月自建成本(¥)",
       "每局成本(API)", "每局成本(自建)", "更划算"]
ws2.append([])
ws2.append(hdr)
for c in ws2[4]:
    c.font = HEAD
    c.fill = HEAD_FILL

daus = [100, 500, 1000, 3000, 5000, 10000, 20000, 50000, 100000, 200000]
for i, d in enumerate(daus):
    r = 5 + i
    ws2.cell(row=r, column=1, value=d)
    ws2.cell(row=r, column=2, value=f"=A{r}*{GAMES_PP}")
    ws2.cell(row=r, column=3, value=f"=B{r}*30")
    ws2.cell(row=r, column=4, value=f"=C{r}*{COST_GAME}")
    ws2.cell(row=r, column=5, value=f"=MAX(1,ROUNDUP(B{r}*{GPU_SEC}/(86400*{UTIL}),0))")
    ws2.cell(row=r, column=6, value=f"=E{r}*{GPU_RENT}+{FIXED}")
    ws2.cell(row=r, column=7, value=f"={COST_GAME}")
    ws2.cell(row=r, column=8, value=f"=F{r}/C{r}")
    ws2.cell(row=r, column=9, value=f'=IF(D{r}<F{r},"API","自建")')
    for col in range(1, 10):
        c = ws2.cell(row=r, column=col)
        c.border = BOX
        c.alignment = Alignment(horizontal="center")
        if col in (4, 6):
            c.number_format = "#,##0"
        if col in (7, 8):
            c.number_format = "0.0000"

for i, w in enumerate([12, 12, 12, 16, 12, 16, 14, 14, 10], start=1):
    ws2.column_dimensions[get_column_letter(i)].width = w

ws2["A17"] = "读法：看最后一列——在你填的参数下，规模涨到哪一档，自建才开始比 API 便宜。"
ws2["A17"].font = Font(italic=True, size=10)

# ---------------- Sheet 3: 收入平衡 ----------------
ws3 = wb.create_sheet("收入平衡")
ws3["A1"] = "基准规模下的收入 / 毛利 / 盈亏平衡点"
ws3["A1"].font = Font(bold=True, size=13)

items = [
    ("DAU", f"={DAU}", "人", "0"),
    ("月局数", f"=B5*{GAMES_PP}*30", "局", "#,##0"),
    ("月 API 成本", f"=B6*{COST_GAME}", "¥", "#,##0"),
    ("自建所需 GPU", f"=MAX(1,ROUNDUP(B6/30*{GPU_SEC}/(86400*{UTIL}),0))", "台", "0"),
    ("月自建成本", f"=B8*{GPU_RENT}+{FIXED}", "¥", "#,##0"),
    ("采用方案", '=IF(B7<B9,"API","自建")', "", "General"),
    ("月算力成本", "=MIN(B7,B9)", "¥", "#,##0"),
    ("付费用户", f"=B5*{CONV}", "人", "#,##0"),
    ("月收入", f"=B12*{PRICE}", "¥", "#,##0"),
    ("月毛利", "=B13-B11", "¥", "#,##0"),
    ("毛利率", "=IF(B13=0,0,B14/B13)", "比例", "0.0%"),
    ("盈亏平衡付费率", f"=IF(B5=0,0,B11/(B5*{PRICE}))", "比例", "0.00%"),
    ("盈亏平衡 ARPU", "=IF(B5=0,0,B11/B5)", "¥/人/月", "0.00"),
]
ws3.append([])
ws3.append(["项目", "数值", "单位"])
for c in ws3[4]:
    c.font = HEAD
    c.fill = HEAD_FILL
for i, (name, formula, unit, fmt) in enumerate(items):
    r = 5 + i
    ws3.cell(row=r, column=1, value=name)
    c = ws3.cell(row=r, column=2, value=formula)
    c.border = BOX
    c.fill = DERIVED_FILL
    c.number_format = fmt
    c.alignment = Alignment(horizontal="center")
    ws3.cell(row=r, column=3, value=unit)

ws3.column_dimensions["A"].width = 22
ws3.column_dimensions["B"].width = 16
ws3.column_dimensions["C"].width = 12

ws3["A20"] = ("注：盈亏平衡付费率 = 算力成本 ÷ (DAU × 会员价)；"
              "意思是每个活跃用户平均要贡献多少钱，才刚好不亏。")
ws3["A20"].font = Font(italic=True, size=10)

# ---------------- Sheet 4: 玩法矩阵 ----------------
ws4 = wb.create_sheet("玩法矩阵")
ws4["A1"] = "各玩法对模型的要求与单局算力成本（量级估算）"
ws4["A1"].font = Font(bold=True, size=13)
hdr4 = ["玩法", "模型档位", "单局 token 量级", "单局 API 成本(¥)", "单局 GPU 秒", "自建适配度", "商业备注"]
ws4.append([])
ws4.append(hdr4)
for c in ws4[4]:
    c.font = HEAD
    c.fill = HEAD_FILL

plays = [
    ("猜词收敛（本项目）", "3B~7B 足够", "3k 输入 / 75 输出", 0.002, 0.8, "★★★★★",
     "纯文字、上下文极短，最适合自建；也是获客入口"),
    ("二十问 / 你问我猜", "7B 足够", "9k / 600", 0.006, 2.4, "★★★★★",
     "规则约束强，小模型不易胡说"),
    ("文字你画我猜 / 联想", "7B 足够", "8k / 260", 0.005, 2.2, "★★★★☆",
     "需要一点空间描述能力，参数稍大更稳"),
    ("故事接龙 / 剧本创作", "14B~32B", "24k / 4.8k", 0.022, 9.2, "★★★☆☆",
     "输出长，自建解码被吃满，API 反而省心"),
    ("狼人杀", "32B+ 或闭源旗舰", "约 900k / 36k", 0.52, 300, "★☆☆☆☆",
     "12 人 × 多轮发言，上下文爆炸；这局输了像 bug，模型必须强"),
    ("剧本杀 / 沉浸跑团", "闭源旗舰 + 长记忆", "约 600k~2M / 几十 k", 0.3, 600, "★☆☆☆☆",
     "要 GM 判案、角色一致性、伏笔回收，目前最贵的一档"),
    ("情感陪伴聊天", "14B~32B + 长期记忆", "单次会话约 200k / 4k", 0.11, 50, "★★★☆☆",
     "记忆是成本主项，也是留存主项，砍不掉"),
]
for i, row in enumerate(plays):
    r = 5 + i
    for j, v in enumerate(row, start=1):
        c = ws4.cell(row=r, column=j, value=v)
        c.border = BOX
        c.alignment = Alignment(vertical="top", wrap_text=(j == 7))
        if j == 4:
            c.number_format = "0.000"

for i, w in enumerate([24, 20, 22, 16, 12, 12, 52], start=1):
    ws4.column_dimensions[get_column_letter(i)].width = w

# ---------------- Sheet 5: 口径说明 ----------------
ws5 = wb.create_sheet("口径说明")
ws5["A1"] = "这份表怎么用、哪些数是猜的"
ws5["A1"].font = Font(bold=True, size=13)
notes = [
    ("改动顺序", "只改「参数假设」里的黄色格；其余三张表全是公式，会自动重算。"),
    ("单价来源", "API 单价按 flash 档量级填的占位值，不是任何厂商的真实报价。"),
    ("GPU 月租", "4090 包月国内约 1200~2000 元，按 1600 填；A100 要贵数倍。"),
    ("吞吐", "7B Q4 + vLLM，预填充 4000、解码 1500 tok/s 是偏乐观的冗余值。"),
    ("利用率 30%", "交互流量集中在晚间 2~3 小时，白天闲置是结构性的，不能按满负荷算。"),
    ("关键结构", "自建付的是「租一张卡」的钱，不是「算一次」的钱——局数越少越亏。"),
    ("没算的部分", "冷启动、模型微调、审核接口、语音 TTS、带宽存储、客服与退款。"),
    ("语音开关", "加 TTS 后成本 ×10~100，届时会压过模型本身，建议单列一行。"),
]
for i, (k, v) in enumerate(notes):
    r = 3 + i
    ws5.cell(row=r, column=1, value=k).font = BOLD
    c = ws5.cell(row=r, column=2, value=v)
    c.alignment = Alignment(wrap_text=True, vertical="top")
    ws5.row_dimensions[r].height = 28
ws5.column_dimensions["A"].width = 16
ws5.column_dimensions["B"].width = 84

wb.save(OUT)
print("saved", OUT)
