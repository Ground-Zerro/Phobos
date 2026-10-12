export default defineClientHandler('update', ({ client }) =>
  Database.installLinks.generate(client.id)
);
