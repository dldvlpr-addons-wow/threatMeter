-- Locale/ruRU.lua
<<<<<<< HEAD
if GetLocale() ~= "ruRU" then return end
local _, NS = ...
local L = NS.L
=======
local _, NS = ...
local L = {}
NS.Locales.ruRU = L
>>>>>>> f337a50ad558bfa5aafa94eaf623bb784d887ead
L.MODE_DAMAGE = "Урон"
L.MODE_HEAL = "Исцеление"
L.MODE_ABSORBS = "Поглощение"
L.MODE_TAKEN = "Полученный урон"
L.MODE_INTERRUPTS = "Прерывания"
L.MODE_DISPELS = "Рассеивания"
L.MODE_DEATHS = "Смерти"
L.MODE_THREAT = "Угроза"
L.FORBIDDEN = "функция отклонена клиентом: %s"
L.UNKNOWN_EVENT = "неизвестное событие пропущено: %s"
L.SESSION_OVERALL = "Всего"
L.SESSION_CURRENT = "Текущий бой"
L.SESSION_UNKNOWN = "Сессия №%s"
L.METER_UNAVAILABLE = "счётчик Blizzard недоступен"
L.THREAT_NO_TARGET = "нет цели"
L.THREAT_UNAVAILABLE = "недоступно в бою на этом клиенте"
L.DETAIL_OUT_OF_COMBAT = "детали других игроков доступны вне боя."
L.MENU_DISPLAY = "Показать"
L.MENU_SESSION = "Сессия"
L.MENU_RESET = "Сбросить"
L.BTN_MENU = "Меню"
L.BTN_RESET = "Сброс"
L.REPORT_NOTHING_THREAT = "в режиме угрозы нечего сообщать"
L.REPORT_NOTHING = "нечего сообщать"
L.REPORT_OUT_OF_COMBAT = "отчёт доступен только вне боя"
L.REPORT_HEADER = "ForeverMeter: %s, %s"
L.MSG_LOCKED = "окно заблокировано"
L.MSG_UNLOCKED = "окно разблокировано"
L.MSG_RESET = "сессии счётчика Blizzard сброшены"
L.MSG_WARN = "предупреждение об угрозе при %d%%"
L.MSG_SOUND = "звук %s"
L.MSG_PETS = "питомцы в режиме угрозы %s"
L.MSG_DEFAULTS = "настройки сброшены"
<<<<<<< HEAD
=======
L.MSG_LANG = "язык: %s"
L.MSG_LANG_LIST = "языки: %s (auto = язык клиента)"
>>>>>>> f337a50ad558bfa5aafa94eaf623bb784d887ead
L.WORD_ON = "вкл"
L.WORD_OFF = "выкл"
L.WORD_SHOWN = "показаны"
L.WORD_HIDDEN = "скрыты"
<<<<<<< HEAD
L.HELP_1 = "/fm mode %s | report [N] | reset | lock | unlock | toggle | scale | rows | width | warn %% | sound | pets | defaults"
L.HELP_2 = "Кнопка Меню или ПКМ по заголовку: выбор режима и сессии. Кнопка Сброс: очистить. Клик по полосе = детали по заклинаниям. Колесо мыши = прокрутка."
=======
L.HELP_1 = "/fm mode %s | report [N] | reset | lock | unlock | toggle | scale | rows | width | windows N | refresh s | warn %% | sound | pets | lang | defaults"
L.HELP_2 = "Кнопка Меню или ПКМ по заголовку: выбор режима и сессии. Кнопка Сброс: очистить. Клик по полосе = детали по заклинаниям. Колесо мыши = прокрутка. Уголок справа внизу = изменить размер."
L.MENU_WINDOWS = "Окна"
L.MENU_LOCK = "Закрепить положение"
L.MENU_NEW_WINDOW = "Новое окно"
L.MENU_CLOSE_WINDOW = "Закрыть это окно"
L.TIP_NO_RECAP = "сводка смерти недоступна"
L.TIP_CLICK = "Клик: детали по заклинаниям"
L.MSG_WINDOWS = "окон: %d"
L.MSG_REFRESH = "обновление каждые %.2f с"
>>>>>>> f337a50ad558bfa5aafa94eaf623bb784d887ead
