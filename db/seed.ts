import 'dotenv/config';
import Database from 'better-sqlite3';

const url = process.env.DATABASE_URL ?? './dev.db';
const dbPath = url.startsWith('file:') ? url.slice(5) : url;

const db = new Database(dbPath);
db.pragma('journal_mode = WAL');

db.exec(`
  CREATE TABLE IF NOT EXISTS task (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    title     TEXT    NOT NULL,
    content   TEXT,
    done      INTEGER NOT NULL DEFAULT 0,
    createdAt TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
  )
`);

const insert = db.prepare(
  'INSERT INTO task (title, content, done) VALUES (?, ?, ?)',
);

const seed = db.transaction(() => {
  insert.run('Configurer la pipeline CI/CD', 'Mettre en place les jobs semantic-release, publish et deploy', 0);
  insert.run('Publier le premier artefact', 'Vérifier que tp-cd-api@1.0.0 apparaît dans Verdaccio', 0);
  insert.run('Valider le déploiement SSH', 'Lancer act -j deploy et vérifier curl http://localhost:3001/health', 0);
  insert.run('Corriger le bug de pagination', 'GET /tasks retourne toujours les 100 premières tâches même avec un filtre', 1);
  insert.run('Ajouter le smoke test de production', 'Health check automatique après chaque déploiement via curl', 0);
});

seed();
db.close();

console.log('Base de données initialisée avec des données de démonstration');
