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

    try {
        const result = await client.query('SELECT * FROM users');
        await client.end();

        return {
            statusCode: 200,
            body: JSON.stringify(result.rows)
        };
    } catch (error) {
        await client.end();

        return {
            statusCode: 500,
            body: JSON.stringify({ error: 'Error fetching users' })
        };
    }
}
