# Character artwork

Choose **Settings → Interface → Artwork → Open Character Art…**, or open the artwork library while choosing a character’s appearance. The Settings action is unavailable during battle. Library changes are saved separately from the preferences draft.

1. Select an existing artwork race to add to its collection, or choose **New race…** to make a named collection such as Tiefling. These names organize artwork; they do not create gameplay races or change character rules.
2. Choose **Import Portraits** or **Import Icons**, then **Choose images…** for multiple files in one directory or **Choose folder…** for all supported images directly inside a folder. Subfolders are not included.
3. Review the batch. Select an image to inspect its native-size result and 4× nearest-pixel preview. Fit preserves proportions with transparent padding; Crop selects a square; Resize fills the square. Nearest sampling is the default; smooth Lanczos sampling is optional.
4. Choose **Import images** to add the ready images. Skipped files remain visible with their reason during review. Cancel import discards the prepared batch.

Portraits become 44×44 PNGs and combat icons become 32×32 PNGs. PNG, JPEG and WebP sources are supported, with at most 256 files, 64 MiB of source data and 16 million decoded pixels per batch. Each source must fit the existing 16 MiB and 2048-pixel-per-edge limits. Original files remain untouched, and the managed library preserves copies.

Select an imported image to rename it, or select multiple imported images to remove them from the selected race. Custom artwork races can also be renamed or removed. Built-in names and stock artwork remain protected. Identical content is stored once and can belong to several races; importing it again into the same race preserves its renamed label.

Character creation’s **Artwork group** filter combines stock recommendations with additions to that group and lists custom collections. Changing the filter preserves the selected portrait and icon. **Use selected artwork** returns a library choice to the appearance draft; existing character edits still require their ordinary Apply action.

Removing library choices never breaks characters already using them. Their image identities and retained payloads remain available, travel with saves and Character Files, and are not silently added back to the picker when those files load. Artwork collection names never enter race eligibility or simulation rules.
