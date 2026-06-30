import VibePetCore

struct SettingsLanguageModel {
    let selectedLanguage: AppLanguage

    init(config: AppConfig) {
        selectedLanguage = config.language
    }

    func configAfterSelecting(_ language: AppLanguage, from config: AppConfig) -> AppConfig {
        config.with(language: language)
    }
}
