# Skywave — macOS menubar радіоплеєр

Нативний SwiftUI `MenuBarExtra`-плеєр для 20 незалежних інтернет-радіостанцій.
Особистий інструмент, не продукт.

## Чому не просто клієнт NTS

nts.live уже має Media Session, service worker і `display:standalone`, тому Safari
«Add to Dock» покриває більшість переваг одиничного клієнта. Існує шість клієнтів NTS,
один живий (`romeovs/nts-desktop`). **Унікальна ніша — мультистанційність**: одне місце
для 20 станцій із різними API. Цього не робить жоден із наявних.

## Зафіксовані рішення — не переобговорювати

- **Лише живий ефір.** Архіву не буде: архівні шоу лежать на SoundCloud, це скрейпінг
  `client_id`, який регулярно ламається. Тому цього ніхто не зробив нормально за 15 років.
- **Жодних вікон.** «Ефіри» і «Моменти» — режими тієї самої панелі (сегментований
  перемикач). Уся перевага над «Add to Dock» — у відсутності вікна.
- **Гучність системна**, слайдера в панелі немає. Натомість сталий `gain` на станцію
  з каталогу. Виміряний розкид між станціями був 19.5 dB.
- **«Моменти» пріоритетніші за ShazamKit.** ~40% ефіру NTS немає навіть на Spotify,
  тож Shazam мовчатиме саме там, де потрібен. 60-секундний кільцевий буфер працює завжди.
- **Каталог — дані, не код.** За півтора року 3 із 24 станцій померли або заснули.
- **Підпис не потрібен** для особистого користування. $99/рік — лише щоб роздавати
  іншим або вмикати ShazamKit.
- Не робимо: iOS-версію, акаунти, шеринг, запис ефірів цілком.

## Технічні факти — перевірені, не припущення

- `MTAudioProcessingTap` **не працює з HLS** — підтверджене обмеження Apple, не баг.
  Для ShazamKit потрібна друга конекція до потоку, а не тап плеєра.
  ⚠️ Виміряно 2026-09-01 на всіх 20 станціях: тап віддає звук лише на **5** —
  обидві SomaFM і три Radiocult. На решті ані `AVAsset`, ані `AVPlayerItem`
  не показують жодної аудіодоріжки, тож чіпляти тап нема до чого. Отже друга
  конекція потрібна не лише для ShazamKit, а й для «Моментів».
- AVPlayer віддає ICY `StreamTitle` сам через `AVPlayerItem.timedMetadata` —
  окремий парсер писати не треба.
- `AVAudioSession` — **iOS-only**, на macOS не потрібен і не налаштовується.
- `LSUIElement = YES` в Info.plist, інакше апка з'явиться в доці.
- `.menuBarExtraStyle(.window)` — не `.menu`, бо далі потрібна власна панель.

## Головний ризик — знято 2026-09-01

**Чи їсть AVPlayer нескінченний Icecast без `Content-Length`?** Так.

Дві станції по 40 хв через `Probe`, обидві **PASS**: нуль `AVPlayerItemPlaybackStalled`,
нуль виходів зі стану `playing`, нуль записів у журналі помилок. SomaFM Drone Zone
перекачала 71.7 МБ рівним потоком 257 kbps.

План Б (власний завантажувач на `URLSession.dataTask` + ручний розбір ICY + подача
в `AVAudioEngine`) **не потрібен**.

⚠️ Побічне: NTS усі 40 хв показував у `accessLog` нулі — `numberOfBytesTransferred`
і `observedBitrate` по нулях, хоча потік ішов без єдиної перерви. **Лічильники
`accessLog` не можна брати за ознаку живого потоку** — сторож у `Resilience`
тримається на `timeControlStatus`, не на байтах.

## Каталог

`stations.json` у цій же теці. 20 станцій, 6 із `favorite: true`.

```json
{ "id": "dublab", "name": "dublab", "city": "Лос-Анджелес",
  "stream": "https://dublab.out.airtime.pro/dublab_a",
  "adapter": "airtime", "adapterId": "dublab",
  "gain": 0.977, "measuredLufs": -15.8, "favorite": true }
```

`gain` присвоюється прямо в `AVPlayer.volume`. Ціль −16 LUFS, виміряно `ffmpeg -af ebur128`.
`AVPlayer.volume` уміє лише прибирати, тож тихіші за ціль станції лишаються на 1.0.

Розподіл: **icy ×11 · airtime ×3 · radiocult ×3 · nts ×1 · radioco ×1 · hls ×1**

## Ендпоінти адаптерів — перевірені живими

```
airtime    GET https://<adapterId>.airtime.pro/api/live-info-v2
           → shows.current.name + tracks.current.name (віддає і назву треку)
           ⚠️ хост API без .out — стрім на <id>.out.airtime.pro, API на <id>.airtime.pro

radiocult  GET https://api.radiocult.fm/api/station/<adapterId>/schedule/live
           → result.status ("schedule" | "offAir") + result.content.title

radioco    GET https://public.radio.co/stations/<adapterId>/status
           → status + current_track.title + history[]

nts        GET https://www.nts.live/api/v2/live
           → results[].now.broadcast_title  (треклісти платні, за Supporter)

icy        метаданих через AVPlayerItem.timedMetadata, окремого запиту немає
hls        The Lot Radio, Livepeer — AVPlayer грає нативно
```

## Що з'ясувалося на реальних відповідях — 2026-09-01

Усі вісім опитуваних станцій відповідають, форма збігається з планом, крім деталей:

- **Radiocult:** назва шоу лежить у `result.content.title`. `result.metadata.title` —
  це ім'я вихідного файлу («Sonic Cynefin w_ Mochyn Daer Aug 3 show.mp3»), годиться
  лише як запасний варіант.
- **Airtime** між шоу віддає `null` замість об'єкта в `shows.current` і `tracks.current`,
  тому кожен вкладений об'єкт декодується поблажливо. Поле `name` треку має вигляд
  «artist - title» і вироджується в « - title.mp3», коли артиста немає, — трек
  збирається з `metadata.artist_name` + `metadata.track_title`.
- **Airtime і NTS** екранують назви в HTML: `I Don&#039;t Wanna`, `&amp;`.

## ICY-метадані — виміряно на всіх 11 станціях

Ідентифікатор елемента — `icy/StreamTitle`, значення читається як рядок. NTS шле
ще й `icy/json`, і там буквально порожній `{}`, тож фільтрувати за ідентифікатором
обов'язково.

- **8 з 11** віддають справжню назву.
- **Kool FM, Rinse FM, SWU FM** (спільна інфраструктура Rinse) шлють незаповнену
  заглушку «Now Playing info goes here» — відсіюється списком сміттєвих значень.
- **SomaFM ×2, Operator Radio** не віддають AVPlayer нічого. Operator узагалі не
  надсилає `icy-metaint`. SomaFM `icy-metaint: 45000` має, але лише під браузерним
  User-Agent; підсунути заголовки через `AVURLAssetHTTPHeaderFieldsKey` не допомогло.
  У SomaFM є власний JSON API — сьомий адаптер, якщо колись знадобиться.

Три станції ще на `http://` (Intergalactic FM, Radio Alhara, ByteFM), тож в
Info.plist прописані поіменні винятки ATS.

## Порядок сесій

0. **AVPlayer + Icecast**, дві захардкоджені станції (NTS, SomaFM Drone Zone).
   Критерій: 30–40 хв безперервної гри без `AVPlayerItemPlaybackStalled`.
1–2. `Catalog` читає JSON · три HTTP-адаптери · ICY · список станцій у панелі.
3. Система: `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`, глобальний хоткей, `SMAppService`.
4. Стійкість: `NSWorkspace.didWakeNotification`, `NWPathMonitor`, автоповтор при застої.
   **Після цієї сесії апка стає постійною**, а не демкою.
5. Моменти: кільцевий буфер 60 с, збереження, список.
6+. Режим «Ефіри», сповіщення, таймер сну, ShazamKit.

## Структура

```
App/       SkywaveApp.swift · AppState.swift
Core/      Player · Resilience · RingBuffer · Catalog
Adapters/  NowPlaying(протокол) · Icy · Airtime · Radiocult · RadioCo · NTS
UI/        PanelView · StationList · OnAirBoard · MomentsList
System/    NowPlayingCenter · Hotkeys
Resources/ stations.json
```

Уся складність — в `Adapters/`. Решта тонка.
