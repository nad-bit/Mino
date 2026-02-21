# Contributing to GitHub Watcher

Thank you for your interest in contributing to GitHub Watcher! This document provides guidelines and instructions for developers.

---

## 🚀 Development Setup

### Prerequisites
- macOS (11 or later)
- Python 3.9 or higher
- Homebrew (optional, for Cask integration testing)

### Getting Started

1. **Clone the repository**:
   ```bash
   git clone https://github.com/nad-bit/GitHub_Watcher.git
   cd GitHub_Watcher
   ```

2. **Create a virtual environment**:
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Run the application**:
   ```bash
   python3 main.py
   ```

---

## 📁 Project Structure

```
GitHub_Watcher/
├── src/
│   ├── app.py            # Main application logic
│   ├── constants.py      # Configuration constants
│   ├── handlers.py       # UI event handlers (NSObject delegates)
│   ├── translations.py   # i18n dictionaries (EN/ES)
│   └── utils.py          # Helper functions
├── main.py               # Entry point
├── icon.icns             # Application icon
└── requirements.txt      # Python dependencies
```

---

## 🎨 Code Style

### General Guidelines
- Follow [PEP 8](https://pep8.org/) style guide
- Use descriptive variable names
- Keep functions under 50 lines when possible
- Add docstrings to all public methods

### Type Hints
- **Required** for all new functions and methods
- Use `from typing import Optional, Dict, List, Any`
- Example:
  ```python
  def fetch_repo_info(self, repo: str) -> Dict[str, Any]:
      """Fetches repository information from GitHub API."""
      ...
  ```

### Logging
Use appropriate logging levels:
- `logging.debug()` - Detailed diagnostic information
- `logging.info()` - Normal operation confirmations
- `logging.warning()` - Recoverable issues (config errors, deprecated usage)
- `logging.error()` - Actual errors that prevent operation

### Constants
- All magic numbers must be defined in `src/constants.py`
- Use `SCREAMING_SNAKE_CASE` for constant names
- Group related constants with comments

---

## 🌍 Internationalization (i18n)

### Adding New Translations

1. Add keys to both `"en"` and `"es"` dictionaries in `src/translations.py`
2. Use descriptive key names: `"errorFetchingRepo"` not `"err1"`
3. Keep messages concise for menu bar UI
4. Test both languages before submitting

Example:
```python
"en": {
    "myNewFeature": "My Feature Name",
    "myNewFeatureMsg": "This is the description"
},
"es": {
    "myNewFeature": "Nombre de mi función",
    "myNewFeatureMsg": "Esta es la descripción"
}
```

---

## 🧪 Testing

### Manual Testing Checklist
Before submitting a PR, verify:
- [ ] App starts without errors
- [ ] Can add a repository (manual and Homebrew)
- [ ] Releases are fetched and displayed correctly
- [ ] Preferences (token, interval, sorting) work
- [ ] Both EN and ES translations display properly
- [ ] Menu bar icon appears and menu opens
- [ ] No memory leaks after leaving app open for 30+ minutes

### Future: Automated Tests
We plan to add `pytest`-based tests. Contributions welcome!

---

## 🔧 Common Tasks

### Adding a New Configuration Option

1. Add default value to `self.config` in `app.py:__init__()`
2. Add UI controls in appropriate dialog method
3. Update `save_config()` if needed
4. Add translations for new UI strings

### Adding a New Menu Item

1. Create callback method in `GitHubWatcherApp` class
2. Add menu item in `build_menu()` method
3. Set callback: `item.set_callback(self.your_callback)`
4. Remember to clear callback in cleanup code

### Modifying API Calls

- Always use `self.session.get()` (not `requests.get()`)
- Include `timeout=const.HTTP_REQUEST_TIMEOUT_SECONDS`
- Add authorization header if `self.config["token"]` exists
- Use `Bearer` token format (not deprecated `token`)

---

## 📝 Pull Request Process

1. **Create a feature branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**:
   - Write clear, descriptive commit messages
   - Keep commits focused and atomic
   - Update documentation if needed

3. **Test thoroughly**:
   - Run the app and verify your changes
   - Check for console errors
   - Test edge cases

4. **Submit PR**:
   - Provide a clear description of changes
   - Reference any related issues
   - Include screenshots for UI changes

5. **Code Review**:
   - Address feedback promptly
   - Keep discussion professional and constructive

---

## 🐛 Reporting Bugs

When reporting bugs, please include:
- macOS version and hardware (Intel/Apple Silicon)
- Python version: `python3 --version`
- Steps to reproduce
- Expected vs actual behavior
- Console logs (if applicable)

---

## 💡 Feature Requests

We welcome feature ideas! When suggesting features:
- Explain the use case
- Consider if it fits the "menu bar app" paradigm
- Propose UI/UX approach
- Discuss performance implications

---

## 📄 License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

## 🙏 Thank You!

Your contributions help make GitHub Watcher better for everyone!
