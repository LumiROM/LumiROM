.class public final Lio/buizel/lumi/FloatingFeatureHooks;
.super Ljava/lang/Object;
.source "FloatingFeatureHooks.java"


# direct methods
.method private constructor <init>()V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method public static onGetBoolean(Ljava/lang/String;)Ljava/lang/Boolean;
    .locals 0

    const/4 p0, 0x0

    return-object p0
.end method

.method public static onGetInt(Ljava/lang/String;)Ljava/lang/Integer;
    .locals 0

    const/4 p0, 0x0

    return-object p0
.end method

.method public static onGetString(Ljava/lang/String;)Ljava/lang/String;
    .locals 2

    const-string v0, "SEC_FLOATING_FEATURE_LAUNCHER_CONFIG_ANIMATION_TYPE"

    invoke-virtual {p0, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v0

    if-eqz v0, :cond_3

    const-string v0, "persist.sys.lumi.launcher_anim_type"

    const/4 v1, 0x1

    invoke-static {v0, v1}, Landroid/os/SemSystemProperties;->getInt(Ljava/lang/String;I)I

    move-result v0

    if-eqz v0, :cond_2

    if-eq v0, v1, :cond_1

    const/4 v1, 0x2

    if-eq v0, v1, :cond_0

    const-string v0, "LowestEnd"

    goto :goto_0

    :cond_0
    const-string v0, "LowEnd"

    goto :goto_0

    :cond_1
    const-string v0, "Mass"

    goto :goto_0

    :cond_2
    const-string v0, "HighEnd"

    goto :goto_0

    :cond_3
    const/4 v0, 0x0

    :goto_0
    return-object v0
.end method
