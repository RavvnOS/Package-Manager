CREATE TABLE IF NOT EXISTS installed_packages (
    name TEXT PRIMARY KEY,
    version TEXT NOT NULL,
    install_date TEXT NOT NULL,
    manifest_path TEXT NOT NULL,
    installed_files TEXT NOT NULL
);
