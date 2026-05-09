# Metroflow-Mobile Development Setup

## Prerequisites

- **Node.js**: 20.11.1 LTS (managed via nvm-windows)
- **pnpm**: Comes with Node.js
- **Expo CLI**: Installed via project dependencies

## Quick Start

### 1. Install Node.js 20.11.1

If you have nvm-windows installed:
```bash
nvm install 20.11.1
nvm use 20.11.1
```

Or download from: https://nodejs.org/dist/v20.11.1/

### 2. Install dependencies
```bash
pnpm install
```

### 3. Start the development server
```bash
pnpm start
# or
expo start
```

## Troubleshooting

### "Body is already read" error
This occurs with Node.js 22.x. Ensure you're using Node 20 LTS:
```bash
node --version  # Should show v20.11.1
```

### Clear Expo cache
```bash
expo start -c
```
