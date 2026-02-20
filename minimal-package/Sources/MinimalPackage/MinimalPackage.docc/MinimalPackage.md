# ``MinimalPackage``

A payment processing SDK supporting multiple regions and terminal types.

## Overview

MinimalPackage consolidates payment features and core logic into a single import.
Add the package to your project and use `import MinimalPackage` to access the full API.

```swift
import MinimalPackage

let terminal = Terminal()
terminal.pay(in: .czechRepublic)
```

## Topics

### Core Types

- ``Country``

### Payment Processing

- ``Terminal``
