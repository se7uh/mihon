---
name: mihon-sync-upstream
description: Sync and merge latest upstream Mihon repository changes (upstream/main) into local fork branches (especially data-saver) while preserving custom data-saver features and resolving known merge conflicts.
---

# Mihon Sync Upstream Skill

This skill provides an automated workflow and step-by-step runbook to pull/sync the latest commits from upstream Mihon (`https://github.com/mihonapp/mihon.git`, branch `main`) into the fork's feature branches (primarily `data-saver`), preserving all data-saver optimizations and resolving known merge conflicts.

## When to Use

Use this skill whenever:
- The user requests to update, sync, or pull from upstream (`mihonapp/mihon`).
- Merging `upstream/main` into `data-saver` or other fork branches.
- Resolving recurring merge conflicts between upstream Mihon changes and the Bandwidth Hero / wsrv.nl data saver implementation.

---

## Quick Execution via Script

A bundled automation script handles fetching, merging, and automatic resolution of known conflict patterns:

```bash
bash .agents/skills/mihon-sync-upstream/scripts/sync_upstream.sh [target_branch]
```
*(Default `target_branch` is `data-saver`).*

---

## Manual Step-by-Step Procedure

### 1. Ensure Remotes & Clean Working Tree

Verify that remotes are configured properly:
- `origin`: `git@github.com-se7uh:se7uh/mihon.git` (or user's fork)
- `upstream`: `https://github.com/mihonapp/mihon.git`

If `upstream` remote is missing:
```bash
git remote add upstream https://github.com/mihonapp/mihon.git
```

Ensure no uncommitted changes in tracked files before proceeding:
```bash
git status
```

### 2. Fetch Latest Upstream

```bash
git fetch upstream main
```

### 3. Switch to Target Branch

```bash
git checkout data-saver
```

### 4. Merge Upstream Main

```bash
git merge upstream/main
```

If the merge completes cleanly without conflicts, proceed to **Step 6**.
If conflicts occur, proceed to **Step 5**.

---

## 5. Conflict Resolution Runbook

The data-saver branch typically conflicts with upstream in the following files. Follow these rules to resolve them:

### A. `.github/workflows/update_website.yml`
- **Issue**: Upstream modifies this workflow, but it is deleted in the fork.
- **Resolution**: Keep it deleted in the fork:
  ```bash
  git rm .github/workflows/update_website.yml
  ```

### B. `app/build.gradle.kts`
- **Issue**: Upstream references `storeFile = file(System.getenv("storeFile"))`, while fork decodes Base64 keystore into `tempStoreFile`. Also, `Base64` import can get dropped during merge.
- **Resolution**: Ensure `import java.util.Base64` is at the top of the file, and use `Base64.getMimeDecoder().decode(...)` (do not write `java.util.Base64` inside the script body, as Gradle shadows the `java` keyword with its Java extension):
  ```kotlin
  // At the top of app/build.gradle.kts:
  import java.util.Base64

  // Inside android { ... }:
  if (System.getenv("MIHON_GITHUB_RELEASE").toBoolean()) {
      val tempStoreFile = file(System.getenv("RUNNER_TEMP")).resolve("antsy.keystore")

      val storeFileBytes = Base64.getMimeDecoder().decode(System.getenv("storeFileBase64"))
      tempStoreFile.outputStream().use { it.write(storeFileBytes) }

      signingConfigs {
          named("debug") {
              storeFile = tempStoreFile
              storePassword = System.getenv("storePassword")
              keyAlias = System.getenv("keyAlias")
              keyPassword = System.getenv("keyPassword")
          }
      }
  }
  ```

### C. `app/src/main/java/eu/kanade/presentation/more/settings/screen/SettingsAdvancedScreen.kt`
- **Issue**: Imports for `SourcePreferences` and `SourcePreferences.DataSaver` conflict with upstream import removals.
- **Resolution**: Keep `SourcePreferences` and `SourcePreferences.DataSaver` imports, and ensure `getDataSaverGroup()` remains registered in the settings items.

### D. `app/src/main/java/eu/kanade/tachiyomi/data/coil/MangaCoverFetcher.kt`
- **Issue**: Upstream moves dependencies into `MangaFactory` / `MangaCoverFactory` constructor, while fork needs `dataSaverLazy` and `sourcePreferences`.
- **Resolution**:
  1. Inject `sourcePreferences` via `private val sourcePreferences: SourcePreferences by injectLazy()` in factories.
  2. Maintain `getSource = { sourceManager.get(...) as? HttpSource }`.
  3. Maintain `dataSaverLazy = coverDataSaver(source, sourcePreferences)` parameter.
  4. Preserve both upstream's `concurrentRequests` and the fork's `coverDataSaver(...)` helper function in the `companion object`.

### E. `app/src/main/java/eu/kanade/tachiyomi/data/download/Downloader.kt`
- **Issue**: Upstream constructor injection via Metro vs fork's `sourcePreferences`.
- **Resolution**:
  1. Add `private val sourcePreferences: SourcePreferences` as a constructor parameter to `Downloader`. Metro will automatically provide it from `AppGraph`.
  2. Keep upstream `@Volatile` modifier on `private var downloaderJob: Job? = null`.

### F. `app/src/main/java/eu/kanade/tachiyomi/data/updater/AppUpdateChecker.kt`
- **Issue**: Upstream renamed `isPreviewBuildType` to `isNightlyBuildType`.
- **Resolution**: Retain fork repo target `se7uh/mihon-preview` (for nightly) and `se7uh/mihon` (for stable):
  ```kotlin
  val GITHUB_REPO: String by lazy {
      if (isNightlyBuildType) {
          "se7uh/mihon-preview"
      } else {
          "se7uh/mihon"
      }
  }
  ```

### G. `app/src/main/java/eu/kanade/tachiyomi/ui/reader/loader/HttpPageLoader.kt`
- **Issue**: Upstream uses new chunk streaming reader with `page.downloadStream`, while fork wraps `DataSaver.getImage(...)`. Also, `Injekt.get()` cannot directly resolve `SourcePreferences` unless bridged or accessed via `Context.appGraph`.
- **Resolution**:
  1. Retrieve `SourcePreferences` via `Injekt.get<Context>().appGraph.sourcePreferences` (and ensure `SourcePreferences` binding is exposed in `MetroInjektRegistrar.kt`).
  2. Maintain `dataSaver` field in `HttpPageLoader`.
  3. In `internalLoadPage`, wrap image loading with `DataSaver.getImage(source, page, dataSaver)` and pass response to `chapterCache.putImageToCache(imageUrl, imageResponse, live)`:
  ```kotlin
  try {
      val imageResponse = DataSaver.getImage(source, page, dataSaver)
      chapterCache.putImageToCache(imageUrl, imageResponse, live)
      live?.finish()
  } catch (e: Throwable) {
      live?.finish(e)
      throw e
  }
  ```

### H. `core/common/src/main/kotlin/tachiyomi/core/common/util/system/ImageUtil.kt`
- **Issue**: Conflict between old tall image splitting methods and upstream's removal of tall image splitting.
- **Resolution**: Accept upstream's version (`git checkout --theirs`) as the reader now renders images in 4MB chunks natively.

---

## 6. Verification and Finalizing Merge

1. Ensure no leftover conflict markers:
   ```bash
   git grep -n -E "^(<<<<<<<|=======|>>>>>>>)"
   ```
2. Verify all intended files are staged:
   ```bash
   git status
   ```
3. Conclude the merge commit:
   ```bash
   git commit --no-edit
   ```
4. Check final commit graph:
   ```bash
   git log --graph --oneline -n 5
   ```
