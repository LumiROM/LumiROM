.class public final Lio/buizel/lumi/settings/LumiSettingsFragment$1;
.super Ljava/lang/Object;
.source "LumiSettingsFragment.java"

# interfaces
.implements Landroidx/appcompat/widget/PopupMenu$OnMenuItemClickListener;


# instance fields
.field public final synthetic this$0:Lio/buizel/lumi/settings/LumiSettingsFragment;


# direct methods
.method public constructor <init>(Lio/buizel/lumi/settings/LumiSettingsFragment;)V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    iput-object p1, p0, Lio/buizel/lumi/settings/LumiSettingsFragment$1;->this$0:Lio/buizel/lumi/settings/LumiSettingsFragment;

    return-void
.end method


# virtual methods
.method public final onMenuItemClick(Landroid/view/MenuItem;)V
    .locals 2

    iget-object p0, p0, Lio/buizel/lumi/settings/LumiSettingsFragment$1;->this$0:Lio/buizel/lumi/settings/LumiSettingsFragment;

    invoke-virtual {p0}, Landroidx/fragment/app/Fragment;->getContext()Landroid/content/Context;

    move-result-object p0

    const-string v0, "power"

    invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;

    move-result-object p0

    check-cast p0, Landroid/os/PowerManager;

    invoke-interface {p1}, Landroid/view/MenuItem;->getItemId()I

    move-result p1

    const/4 v0, 0x1

    if-eq p1, v0, :cond_1

    const/4 v1, 0x2

    if-eq p1, v1, :cond_0

    const/4 p1, 0x0

    goto :goto_0

    :cond_0
    const-string p1, "download"

    goto :goto_0

    :cond_1
    const-string p1, "recovery"

    :goto_0
    invoke-virtual {p0, p1}, Landroid/os/PowerManager;->reboot(Ljava/lang/String;)V

    return-void
.end method
