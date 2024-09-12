import pg from 'pg'
const Client = pg.Client

export async function handler(event) {
    const client = new Client({
        host: process.env.DB_HOST,
        user: process.env.DB_USER,
        password: process.env.DB_PASSWORD,
        database: process.env.DB_NAME
    });

    await client.connect();

    const createTableQuery = `
      CREATE TABLE IF NOT EXISTS users (
        userId SERIAL PRIMARY KEY,
        userName TEXT NOT NULL
      );
    `;

    try {
        await client.query(createTableQuery);
        await client.end();
        return {
            statusCode: 200,
            body: JSON.stringify({ message: 'Table created successfully' })
        };
    } catch (error) {
        await client.end();
        return {
            statusCode: 500,
            body: JSON.stringify({ error: 'Error creating table' })
        };
    }
}
