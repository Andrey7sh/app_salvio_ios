# Материалы карточки App Store

`screenshots/iphone-6.9/`: шесть продающих кадров 1320×2868 (iPhone 6.9", обязательный размер App Store),
порядок как в карточке RuStore. Сводный лист: `screenshots/_все_кадры.jpg`.

Откуда экраны: настоящая iPhone-версия, снятая в CI без Mac. Воркфлоу `.github/workflows/appstore-screens.yml`
собирает debug-сборку, запускает её на симуляторе Pro Max с `-demoScreen <экран>` (данные из `Salvio/DemoMode.swift`)
и отдаёт сырые снимки артефактом `appstore-raw-screens`.

Как пересобрать кадры после изменения текстов: скачать артефакт в `_исходники/src/`, затем на Windows
`python _исходники/make.py` (нужны Chrome и Pillow), готовые JPG появятся в `_исходники/out/`.
