# Relock After Unlock

[English](#english) · [Русский](#русский)

## English

Relock After Unlock is a macOS menu bar utility that locks your screen **30 or 60 minutes after you unlock it**, even while you are using your Mac.

Click the lock in the menu bar to choose an interval or see the scheduled lock time. Changing the interval during a countdown recalculates the deadline from the last unlock. If the shorter interval has already elapsed, the screen locks immediately. Locking the screen yourself cancels the countdown. The interval is saved, and each new unlock starts a fresh countdown.

### Build and install

The build targets Apple Silicon and macOS 27.0 or later. The development Mac runs macOS 27.0.1. Install Apple Command Line Tools with `xcode-select --install` if needed.

```sh
git clone --branch v2.1 https://github.com/vivalerievich/relock-after-unlock.git
cd relock-after-unlock
make build
make install
```

`make build` creates `build/RelockAfterUnlock.app`. `make install` also builds the app if needed, installs it for the current user, and starts a LaunchAgent that runs at login. Run it from your macOS desktop session without `sudo`. The first countdown starts after your next unlock. To replace an existing installation, run `make uninstall` first.

```sh
make uninstall
```

Uninstall stops the agent and removes the installed app and LaunchAgent. It keeps your saved interval.

The app uses private macOS screen lock APIs and notifications, which may change with macOS updates. This release is distributed as source for local builds.

## Русский

Relock After Unlock блокирует экран Mac **через 30 или 60 минут после разблокировки**, даже если ты продолжаешь работать. Оставшееся время видно рядом со значком замка в строке меню.

Нажми на замок, чтобы выбрать интервал или посмотреть время блокировки. При смене интервала срок пересчитывается от последней разблокировки. Если более короткий интервал уже истёк, экран блокируется сразу. Ручная блокировка отменяет отсчёт. Приложение запоминает выбранный интервал, и при каждой разблокировке отсчёт начинается заново.

### Сборка и установка

Сборка рассчитана на Apple Silicon и macOS 27.0 или новее. На Mac, где разрабатывалась утилита, установлена macOS 27.0.1. Если Apple Command Line Tools ещё не установлены, выполни `xcode-select --install`.

```sh
git clone --branch v2.1 https://github.com/vivalerievich/relock-after-unlock.git
cd relock-after-unlock
make build
make install
```

`make build` создаёт `build/RelockAfterUnlock.app`. `make install` при необходимости собирает приложение, устанавливает его для текущего пользователя и запускает LaunchAgent. Он запускается при каждом входе в учётную запись. Выполняй команду в графическом сеансе macOS без `sudo`. Первый отсчёт начнётся при следующей разблокировке. Для замены установленной версии сначала выполни `make uninstall`.

```sh
make uninstall
```

Команда остановит агент и удалит установленное приложение и LaunchAgent. Выбранный интервал сохранится.

Утилита использует закрытые API и уведомления о блокировке macOS. После обновления системы их поведение может измениться. Релиз содержит исходники для локальной сборки.

## License / Лицензия

[MIT](LICENSE)
