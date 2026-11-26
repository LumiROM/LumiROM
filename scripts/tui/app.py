"""Textual interface for ``build_local.sh``.

Form on the right, embedded terminal on the left, output files at the bottom.
The form maps one-to-one to :class:`scripts.tui.state.BuildConfig`; this module
only wires widgets to it, it does not build anything itself.
"""

from __future__ import annotations

import time

from textual import on
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.widgets import (
    Button,
    Footer,
    Header,
    Input,
    Label,
    Select,
    Static,
    Switch,
)
from textual_tty import Terminal

from .state import (
    BuildConfig,
    REPO_ROOT,
    default_maintainer,
    find_outputs,
    human_size,
    load_state,
    save_state,
)
from .widgets.params_panel import ParamsPanel

CSS = """
Screen {
    background: $surface;
}

#body {
    height: 1fr;
}

#left {
    width: 1fr;
    border: round $primary;
    padding: 0 1;
}

#right {
    width: 46;
    border: round $secondary;
    padding: 0 1;
}

.panel-title {
    text-style: bold;
    padding: 1 0 0 0;
}

.field-label {
    color: $text-muted;
    padding-top: 1;
}

.hint {
    color: $text-muted;
}

#preview {
    padding: 1 0 0 0;
    color: $success;
}

#status {
    padding: 1 0;
}

#terminal-host {
    height: 1fr;
    border-top: solid $panel;
}

.switch-row {
    height: auto;
    align: left middle;
}

.switch-label {
    padding-left: 1;
    width: 1fr;
    content-align: left middle;
}

.button-row {
    height: auto;
    padding-top: 1;
    layout: grid;
    grid-size: 2 2;
    grid-columns: 1fr 1fr;
    grid-gutter: 0 1;
}

.button-row Button {
    width: 100%;
    min-width: 0;
    height: 3;
    margin: 0;
}

#start {
    column-span: 2;
}
"""


class LumiTUI(App):
    TITLE = "LumiROM Builder"
    CSS = CSS
    BINDINGS = [
        Binding("ctrl+q", "quit", "Quit", priority=True),
        Binding("ctrl+x", "cancel_build", "Cancel build", priority=True),
        Binding("ctrl+s", "save", "Save", priority=True),
    ]

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        with Horizontal(id="body"):
            with Vertical(id="left"):
                yield Label("Command preview", classes="panel-title")
                yield Static("", id="preview")
                yield Static("", id="status")
                yield Label("Terminal", classes="panel-title")
                yield Vertical(id="terminal-host")
            yield ParamsPanel(id="right")
        yield Footer()

    def on_mount(self) -> None:
        self.params = self.query_one(ParamsPanel)
        self._build_active = False
        self._cancelled = False
        self._started_at = 0.0

        cfg = load_state()
        if not cfg.maintainer:
            cfg.maintainer = default_maintainer()
        self.params.apply_config(cfg)
        self.params.update_imei_tip(cfg.stock)
        self._refresh()
        self.query_one("#status", Static).update(
            "[b]Idle[/b]\nFill the form and press Start Build."
        )

    def _refresh(self) -> None:
        cfg = self.params.read_config()
        if cfg.stock:
            preview = cfg.command()
        else:
            preview = "bash build_local.sh -s <device> -c <CSC> -i <IMEI> [options]"
        self.query_one("#preview", Static).update(preview)

        if self._build_active:
            return

        errors = cfg.validate()
        status = self.query_one("#status", Static)
        if errors:
            bullets = "\n".join(f"  [red]x[/red] {error}" for error in errors)
            status.update(f"[b]Incomplete[/b]\n{bullets}")
        else:
            status.update("[b][green]Ready to build[/green][/b]")

    @on(Select.Changed, "#stock")
    def stock_changed(self, event: Select.Changed) -> None:
        stock = event.value if isinstance(event.value, str) else ""
        self.params.update_imei_tip(stock)
        self._refresh()

    @on(Input.Changed)
    def input_changed(self, event: Input.Changed) -> None:
        if event.input.id == "csc":
            upper = event.input.value.upper()
            if upper != event.input.value:
                event.input.value = upper
                event.input.cursor_position = len(upper)
        self._refresh()

    @on(Switch.Changed)
    def switch_changed(self, event: Switch.Changed) -> None:
        self._refresh()

    @on(Button.Pressed, "#start")
    async def start_pressed(self) -> None:
        if self._build_active:
            self.action_cancel_build()
            return

        cfg = self.params.read_config()
        errors = cfg.validate()
        if errors:
            self.notify("Fix the highlighted fields first.", severity="error")
            status = self.query_one("#status", Static)
            bullets = "\n".join(f"  [red]x[/red] {error}" for error in errors)
            status.update(f"[b]Incomplete[/b]\n{bullets}")
            return

        save_state(cfg)
        self._started_at = time.time()
        self._cancelled = False
        self._set_running(True)
        self.query_one("#status", Static).update(
            "[b][yellow]Building...[/yellow][/b]\n"
            "Interact with the terminal as needed (e.g. sudo password). "
            "Press Ctrl+X or Cancel Build to stop."
        )

        host = self.query_one("#terminal-host")
        await host.remove_children()
        terminal = Terminal(command=cfg.pty_command(), id="terminal")
        await host.mount(terminal)
        terminal.focus()

    @on(Button.Pressed, "#save")
    def save_pressed(self) -> None:
        self.action_save()

    @on(Button.Pressed, "#reset")
    def reset_pressed(self) -> None:
        if self._build_active:
            return
        cfg = BuildConfig(maintainer=default_maintainer())
        self.params.apply_config(cfg)
        self.params.update_imei_tip(cfg.stock)
        self._refresh()
        self.notify("Form reset.")

    @on(Terminal.ProcessExited)
    def terminal_exited(self, event: Terminal.ProcessExited) -> None:
        if not self._build_active:
            return
        self._set_running(False)
        self._show_results(event.exit_code)

    def _set_running(self, running: bool) -> None:
        self._build_active = running
        for widget in self.params.query("Input, Select, Switch"):
            widget.disabled = running
        self.query_one("#save", Button).disabled = running
        self.query_one("#reset", Button).disabled = running

        start = self.query_one("#start", Button)
        start.label = "Cancel Build" if running else "Start Build"
        start.variant = "error" if running else "success"

    def _show_results(self, code: int) -> None:
        if self._cancelled:
            lines = ["[b][yellow]Build cancelled.[/yellow][/b]"]
            self.notify("Build cancelled.", severity="warning")
        elif code == 0:
            lines = ["[b][green]Build finished successfully.[/green][/b]"]
            self.notify("Build finished successfully.", severity="information")
        else:
            lines = [f"[b][red]Build failed (exit {code}).[/red][/b] Check LOGS/."]
            self.notify("Build failed. Check the terminal and LOGS/.", severity="error")

        outputs = find_outputs(started=self._started_at)
        if outputs:
            lines.append("")
            lines.append("[b]Artifacts:[/b]")
            for path in outputs:
                try:
                    size = human_size(path.stat().st_size)
                    rel = path.relative_to(REPO_ROOT)
                except OSError:
                    size = "?"
                    rel = path
                lines.append(f"  [cyan]{rel}[/cyan] ({size})")
        self.query_one("#status", Static).update("\n".join(lines))

    def _terminal(self) -> Terminal | None:
        found = self.query("#terminal")
        return found.first() if found else None

    def action_cancel_build(self) -> None:
        if not self._build_active:
            return
        self._cancelled = True
        terminal = self._terminal()
        if terminal is not None:
            terminal.blur()
            terminal.board.stop_process()
        self.notify("Cancelling build...", severity="warning")

    def action_save(self) -> None:
        save_state(self.params.read_config())
        self.notify("Configuration saved.")

    def action_quit(self) -> None:
        terminal = self._terminal()
        if terminal is not None:
            terminal.board.stop_process()
        self.exit()


if __name__ == "__main__":
    LumiTUI().run()
