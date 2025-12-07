# Archive

Outdated documentation, completed investigations, and superseded implementation summaries.

**Note**: This folder contains historical documentation that is no longer actively maintained but preserved for reference.

## Contents

### Completed Work
- **[IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)** - OSC-based audio visualization implementation (completed)
  - Detailed summary of completed Python → OSC → Processing pipeline
  - Performance metrics and test results
  - Comprehensive feature comparison
  - **Status**: Implementation complete, documentation superseded by operation guides

### Investigations
- **[shader-centering-investigation.md](shader-centering-investigation.md)** - GLSL shader centering issue investigation (Dec 6, 2025)
  - Problem: Circular shaders offset toward bottom-left
  - Investigation timeline and attempted solutions
  - Resolution status and lessons learned
  - **Status**: Issue resolved, kept for historical reference

## Why Archive?

Documents are moved to archive when:

1. **Implementation Complete**: The work described is finished and integrated
2. **Superseded**: Newer documentation covers the same topic better
3. **Outdated Technology**: The approach is no longer recommended
4. **Historical Reference**: Useful to understand past decisions but not current practice
5. **Investigation Complete**: Issue resolved, kept for debugging similar problems

## Active Documentation

For current documentation, see:

- **[Setup Guides](../setup/)** - Installation and configuration
- **[Operation Guides](../operation/)** - How to use the system
- **[Reference Documentation](../reference/)** - Technical details and APIs
- **[Development Plans](../development/)** - Active implementation plans

## Archived Document Index

| Document | Date | Reason | Replaced By |
|----------|------|--------|-------------|
| IMPLEMENTATION_SUMMARY.md | 2024 | Implementation complete | [Quick Start OSC Pipeline](../setup/QUICK_START_OSC_PIPELINE.md), [Python VJ README](../../python-vj/README.md) |
| shader-centering-investigation.md | Dec 2025 | Investigation complete | Resolved in VJUniverse code |

## Using Archived Documents

### When to Reference
- Understanding historical design decisions
- Debugging similar issues to past investigations
- Learning from completed implementation approaches
- Researching why certain features were built

### When NOT to Reference
- For current setup instructions (use [Setup Guides](../setup/) instead)
- For active development (use [Development Plans](../development/) instead)
- For operational procedures (use [Operation Guides](../operation/) instead)
- For technical reference (use [Reference Documentation](../reference/) instead)

## Document Preservation Policy

Archived documents are:
- ✅ Kept in version control
- ✅ Preserved for historical reference
- ✅ Clearly marked as archived
- ❌ Not actively maintained
- ❌ Not guaranteed to be current
- ❌ Not updated for new features

## Cleanup Process

Documents move to archive when:
1. Newer documentation supersedes them completely
2. Implementation is finished and integrated
3. Technology/approach is deprecated
4. Investigation is complete and closed

Documents are removed (not archived) when:
1. Content is completely irrelevant
2. Contains sensitive information (moved to private notes)
3. Duplicates other archived content
4. Never used and provides no value

## See Also

- [Main Documentation](../README.md) - Documentation hub
- [Development Plans](../development/) - Active future work
