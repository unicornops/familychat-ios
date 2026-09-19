### Pull Request Checklist

- [ ] The title follows [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) (e.g. `feat(brand): …`).
- [ ] The change is as small as possible, so that merges from upstream Element X stay cheap.
- [ ] Any change to `app.yml`, `project.yml` or a `target.yml` has been regenerated with `xcodegen`.

**UI changes have been tested with:**
- [ ] iPhone and iPad simulators in portrait and landscape orientations.
- [ ] Dark mode enabled and disabled.
- [ ] Various sizes of dynamic type.
- [ ] Voiceover enabled.
