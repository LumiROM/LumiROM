from __future__ import annotations

from textual.app import ComposeResult
from textual.containers import Horizontal, VerticalScroll
from textual.widgets import Button, Input, Label, Select, Static, Switch

from ..state import BuildConfig, example_imei_for, list_devices


class ParamsPanel(VerticalScroll):
    def compose(self) -> ComposeResult:
        devices = list_devices()
        yield Label("Build Parameters", classes="panel-title")

        yield Label("Stock device", classes="field-label")
        yield Select(
            [(device, device) for device in devices],
            prompt="Select a device",
            id="stock",
        )

        yield Label("CSC / region (3 letters)", classes="field-label")
        yield Input(placeholder="e.g. EUX", restrict=r"[A-Za-z]*", max_length=3, id="csc")

        yield Label("IMEI of the base device (15 digits)", classes="field-label")
        yield Input(placeholder="15 digits", restrict=r"[0-9]*", max_length=15, id="imei")
        yield Static("", id="imei-tip", classes="hint")

        yield Label("Maintainer", classes="field-label")
        yield Input(placeholder="GitHub or Telegram username", id="maintainer")

        yield Label("Options", classes="field-label")
        with Horizontal(classes="switch-row"):
            yield Switch(value=True, id="use-mods")
            yield Label("Include mods", classes="switch-label")
        with Horizontal(classes="switch-row"):
            yield Switch(value=True, id="use-ai")
            yield Label("Include Galaxy AI", classes="switch-label")
        with Horizontal(classes="switch-row"):
            yield Switch(value=False, id="bpf")
            yield Label("BPF legacy kernel (< 5.10)", classes="switch-label")
        with Horizontal(classes="switch-row"):
            yield Switch(value=False, id="imgzip")
            yield Label("Deliver partition images (.img ZIP)", classes="switch-label")
        with Horizontal(classes="switch-row"):
            yield Switch(value=False, id="no-target-files")
            yield Label("Skip target files (test builds)", classes="switch-label")

        yield Label("Incremental from (optional)", classes="field-label")
        yield Input(placeholder="e.g. 8.6.4", id="incremental")

        with Horizontal(classes="button-row"):
            yield Button("Start Build", variant="success", id="start")
            yield Button("Save", id="save")
            yield Button("Reset", id="reset")

    def read_config(self) -> BuildConfig:
        stock = self.query_one("#stock", Select).value
        return BuildConfig(
            stock=stock if isinstance(stock, str) else "",
            csc=self.query_one("#csc", Input).value.strip().upper(),
            imei=self.query_one("#imei", Input).value.strip(),
            maintainer=self.query_one("#maintainer", Input).value.strip(),
            use_mods=self.query_one("#use-mods", Switch).value,
            use_ai=self.query_one("#use-ai", Switch).value,
            bpf_legacy=self.query_one("#bpf", Switch).value,
            img_zip=self.query_one("#imgzip", Switch).value,
            skip_target_files=self.query_one("#no-target-files", Switch).value,
            incremental_from=self.query_one("#incremental", Input).value.strip(),
        )

    def apply_config(self, cfg: BuildConfig) -> None:
        if cfg.stock in list_devices():
            self.query_one("#stock", Select).value = cfg.stock
        self.query_one("#csc", Input).value = cfg.csc
        self.query_one("#imei", Input).value = cfg.imei
        self.query_one("#maintainer", Input).value = cfg.maintainer
        self.query_one("#use-mods", Switch).value = cfg.use_mods
        self.query_one("#use-ai", Switch).value = cfg.use_ai
        self.query_one("#bpf", Switch).value = cfg.bpf_legacy
        self.query_one("#imgzip", Switch).value = cfg.img_zip
        self.query_one("#no-target-files", Switch).value = cfg.skip_target_files
        self.query_one("#incremental", Input).value = cfg.incremental_from

    def update_imei_tip(self, stock: str) -> None:
        example = example_imei_for(stock)
        tip = self.query_one("#imei-tip", Static)
        if example:
            tip.update(f"Tip: example IMEI for {stock} base device -> {example}")
        else:
            tip.update("")
