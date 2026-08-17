# Future sync layer

Local Dexie repositories implement the domain repository ports. A future
Supabase sync adapter belongs in this directory and must preserve those ports,
so neither UI components nor domain types need to depend on a backend client.
