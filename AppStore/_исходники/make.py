"""Продающие скриншоты App Store 1320x2868 (iPhone 6.9"): HTML -> headless Chrome -> JPG.

Вёрстка в координатах 1080 по ширине, Chrome рендерит с масштабом 1320/1080.
Исходные экраны (src/*.png) снимает CI: .github/workflows/appstore-screens.yml, артефакт appstore-raw-screens.
"""
import os
import subprocess

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "src").replace("\\", "/")
OUT = os.path.join(HERE, "out")
os.makedirs(OUT, exist_ok=True)
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"

CHECK = ('<svg viewBox="0 0 24 24" width="34" height="34"><circle cx="12" cy="12" r="12" fill="#FFB000"/>'
         '<path d="M7 12.5l3.2 3.2L17 9" stroke="#111" stroke-width="2.6" fill="none" stroke-linecap="round" '
         'stroke-linejoin="round"/></svg>')

CSS = """
@import url('https://fonts.googleapis.com/css2?family=Manrope:wght@500;700;800&display=block');
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { width: 1080px; height: 2347px; overflow: hidden; }
body { font-family: 'Manrope', 'Segoe UI', sans-serif; color: #fff; position: relative;
  background: radial-gradient(900px 700px at 85% 8%, rgba(255,176,0,.22), transparent 70%),
              radial-gradient(800px 800px at 0% 100%, rgba(255,176,0,.10), transparent 70%), #0B0B0C; }
.brand { position: absolute; left: 80px; top: 78px; display: flex; align-items: center; gap: 18px;
  font-size: 32px; font-weight: 700; color: #C9C9CE; }
.brand img { width: 60px; height: 60px; border-radius: 16px; }
h1 { position: absolute; left: 80px; right: 80px; top: 186px; font-size: 92px; line-height: 1.04;
  font-weight: 800; letter-spacing: -2px; }
h1 em { font-style: normal; color: #FFB000; }
.sub { position: absolute; left: 80px; right: 120px; font-size: 40px; line-height: 1.3; font-weight: 500; color: #B9B9BF; }
.phone { position: absolute; left: 152px; width: 776px; padding: 18px; border-radius: 118px; background: #1D1D20;
  box-shadow: 0 0 0 3px #2c2c30, 0 50px 140px rgba(255,176,0,.20), 0 30px 80px rgba(0,0,0,.6); }
.screen { width: 740px; height: 1608px; border-radius: 100px; overflow: hidden; background: #000; }
.screen img { width: 740px; display: block; }
.pills { position: absolute; left: 80px; right: 60px; display: flex; flex-wrap: wrap; gap: 18px; }
.pills .chip { position: static; max-width: none; white-space: nowrap; }
.zoom { position: absolute; left: 60px; right: 60px; border-radius: 36px; overflow: hidden; background: #000;
  box-shadow: 0 0 0 4px #FFB000, 0 40px 100px rgba(0,0,0,.7); }
.zoom img { display: block; width: 100%; }
.chip { position: absolute; display: flex; align-items: center; gap: 16px; padding: 18px 28px 18px 18px;
  border-radius: 30px; background: #fff; color: #111; font-size: 32px; font-weight: 700; line-height: 1.15;
  box-shadow: 0 24px 60px rgba(0,0,0,.55); max-width: 560px; }
.chip.y { background: #FFB000; }
.chip.y svg circle { fill: #111; } .chip.y svg path { stroke: #FFB000; }
.steps { position: absolute; left: 80px; right: 80px; top: 760px; display: flex; flex-direction: column; gap: 56px; }
.step { display: flex; align-items: center; gap: 36px; padding: 56px 48px; border-radius: 44px;
  background: #18181B; box-shadow: inset 0 0 0 2px #2a2a2e; }
.num { flex: none; width: 104px; height: 104px; border-radius: 52px; background: #FFB000; color: #111;
  display: flex; align-items: center; justify-content: center; font-size: 56px; font-weight: 800; }
.step b { display: block; font-size: 46px; line-height: 1.15; }
.step span { display: block; margin-top: 8px; font-size: 32px; color: #A9A9AF; font-weight: 500; }
.foot { position: absolute; left: 80px; right: 80px; bottom: 110px; text-align: center; font-size: 36px;
  color: #C9C9CE; font-weight: 600; }
.foot em { font-style: normal; color: #FFB000; }
"""


def page(body):
    return (f'<!doctype html><html lang="ru"><head><meta charset="utf-8"><style>{CSS}</style></head><body>'
            f'<div class="brand"><img src="file:///{SRC}/icon.png">Salvio · ИИ-диктофон</div>{body}</body></html>')


def phone_slide(title, sub, pills, shot, top, zoom=None):
    """Заголовок, подзаголовок, плашки-выгоды строкой и телефон, уходящий за нижний край.
    top: (подзаголовок, плашки, телефон) по вертикали. zoom: (y0, y1, верх выноски) увеличенный кусок экрана."""
    sub_top, pills_top, phone_top = top
    pills_html = "".join(f'<div class="chip{" y" if y else ""}">{CHECK}<span>{t}</span></div>' for t, y in pills)
    z = ""
    if zoom:
        y0, y1, ztop = zoom
        crop = f"{shot[:-4]}_zoom.png"
        Image.open(os.path.join(SRC, shot)).crop((0, y0, 1320, y1)).save(os.path.join(SRC, crop))
        z = f'<div class="zoom" style="top:{ztop}px"><img src="file:///{SRC}/{crop}"></div>'
    return page(f'<h1>{title}</h1><div class="sub" style="top:{sub_top}px">{sub}</div>'
                f'<div class="pills" style="top:{pills_top}px">{pills_html}</div>'
                f'<div class="phone" style="top:{phone_top}px"><div class="screen">'
                f'<img src="file:///{SRC}/{shot}"></div></div>{z}')


NB = "&nbsp;"
SLIDES = {
    "1_itogi": phone_slide(
        "Встреча закончилась,<br><em>итоги уже готовы</em>", "Текст разговора и краткий итог<br>через несколько минут",
        [("Кто что сказал", False), ("Договорённости и задачи", False), ("30 минут бесплатно", True)],
        "meeting.png", (585, 725, 900)),
    "2_pamyat": phone_slide(
        "Ничего не забудете,<br><em>ИИ всё запомнит</em>", "Цифры, сроки, имена и решения<br>сохранятся без потерь",
        [("Полный текст разговора", False), ("Задачи и сроки на месте", False)],
        "planning.png", (420, 560, 760), zoom=(1780, 2150, 1720)),
    "3_fon": phone_slide(
        f"Пишет в кармане<br><em>с{NB}выключенным экраном</em>", "Двухчасовое совещание запишется целиком",
        [("Пауза одной кнопкой", False), ("Работает без интернета", False)],
        "record.png", (520, 615, 740)),
    "4_konspekt": phone_slide(
        f"Лекция сама<br>превращается <em>в{NB}конспект</em>", "Тезисы, термины, примеры и цитаты",
        [("Учёба и вебинары", False), ("Не нужно писать от руки", False)],
        "lecture.png", (520, 615, 740)),
    "5_zapisi": phone_slide(
        f"Все записи<br><em>в{NB}одном месте</em>", "Встречи, планёрки, звонки и заметки.<br>На телефоне и в веб-кабинете",
        [("Поиск по тексту в вебе", False), ("Итог по ссылке в любой мессенджер", False)],
        "list.png", (420, 560, 760)),
    "6_besplatno": page(
        '<h1><em>30 минут</em><br>бесплатно</h1><div class="sub" style="top:395px">'
        'Без подписки: платите только<br>за минуты записи</div>'
        '<div class="steps" style="top:700px">'
        '<div class="step"><div class="num">1</div><div><b>Нажмите «Начать запись»</b><span>перед встречей, лекцией или звонком</span></div></div>'
        '<div class="step"><div class="num">2</div><div><b>Уберите телефон</b><span>говорите как обычно, экран можно выключить</span></div></div>'
        '<div class="step"><div class="num">3</div><div><b>Получите текст и итоги</b><span>по собеседникам, с задачами и договорённостями</span></div></div>'
        '</div><div class="foot">Неиспользованные минуты <em>не сгорают</em></div>'),
}

for name, html in SLIDES.items():
    src = os.path.join(OUT, name + ".html")
    open(src, "w", encoding="utf-8").write(html)
    png = os.path.join(OUT, name + ".png")
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1.2222222",
                    "--allow-file-access-from-files", "--virtual-time-budget=6000", "--window-size=1080,2347",
                    f"--screenshot={png}", "file:///" + src.replace("\\", "/")], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    im = Image.open(png).convert("RGB")
    im = im.crop((0, 0, 1320, 2868))  # Chrome округляет масштаб до 2869 строк, лишняя внизу
    assert im.size == (1320, 2868), im.size
    im.save(os.path.join(OUT, name + ".jpg"), quality=92)
    print(name, os.path.getsize(os.path.join(OUT, name + ".jpg")) // 1024, "KB")
