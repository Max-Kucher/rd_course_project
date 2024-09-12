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

    const { userId, userName } = JSON.parse(event.body);

    const query = 'INSERT INTO users(userId, userName) VALUES($1, $2)';
    const values = [userId, userName];

    try {
        await client.query(query, values);
        await client.end();

        return {
            statusCode: 200,
            body: JSON.stringify({ message: 'User added successfully' })
        };
    } catch (error) {
        await client.end();

        return {
            statusCode: 500,
            body: JSON.stringify({ error: 'Error adding user' })
        };
    }
}
