.class public final Lio/buizel/lumi/search/LumiSearchIndexableResources;
.super Lcom/android/settingslib/search/SearchIndexableResourcesMobile;
.source "LumiSearchIndexableResources.java"


# direct methods
.method public constructor <init>()V
    .locals 3

    invoke-direct {p0}, Lcom/android/settingslib/search/SearchIndexableResourcesMobile;-><init>()V

    new-instance v0, Lcom/android/settingslib/search/SearchIndexableData;

    const-class v1, Lio/buizel/lumi/settings/LumiSettingsFragment;

    sget-object v2, Lio/buizel/lumi/settings/LumiSettingsFragment;->SEARCH_INDEX_DATA_PROVIDER:Lcom/android/settings/search/BaseSearchIndexProvider;

    invoke-direct {v0, v1, v2}, Lcom/android/settingslib/search/SearchIndexableData;-><init>(Ljava/lang/Class;Lcom/android/settingslib/search/Indexable$SearchIndexProvider;)V

    invoke-virtual {p0, v0}, Lio/buizel/lumi/search/LumiSearchIndexableResources;->addIndex(Lcom/android/settingslib/search/SearchIndexableData;)V

    new-instance v0, Lcom/android/settingslib/search/SearchIndexableData;

    const-class v1, Lio/buizel/lumi/settings/extra/ExtraSettingsFragment;

    sget-object v2, Lio/buizel/lumi/settings/extra/ExtraSettingsFragment;->SEARCH_INDEX_DATA_PROVIDER:Lcom/android/settings/search/BaseSearchIndexProvider;

    invoke-direct {v0, v1, v2}, Lcom/android/settingslib/search/SearchIndexableData;-><init>(Ljava/lang/Class;Lcom/android/settingslib/search/Indexable$SearchIndexProvider;)V

    invoke-virtual {p0, v0}, Lio/buizel/lumi/search/LumiSearchIndexableResources;->addIndex(Lcom/android/settingslib/search/SearchIndexableData;)V

    new-instance v0, Lcom/android/settingslib/search/SearchIndexableData;

    const-class v1, Lio/buizel/lumi/settings/ui/UISettingsFragment;

    sget-object v2, Lio/buizel/lumi/settings/ui/UISettingsFragment;->SEARCH_INDEX_DATA_PROVIDER:Lcom/android/settings/search/BaseSearchIndexProvider;

    invoke-direct {v0, v1, v2}, Lcom/android/settingslib/search/SearchIndexableData;-><init>(Ljava/lang/Class;Lcom/android/settingslib/search/Indexable$SearchIndexProvider;)V

    invoke-virtual {p0, v0}, Lio/buizel/lumi/search/LumiSearchIndexableResources;->addIndex(Lcom/android/settingslib/search/SearchIndexableData;)V

    return-void
.end method
