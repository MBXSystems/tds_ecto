Code.require_file "../deps/ecto/integration_test/support/types.exs", __DIR__

defmodule Tds.Ecto.TdsTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Ecto.Queryable
  alias Tds.Ecto.Connection, as: SQL
  
  defmodule Model do
    use Ecto.Schema

    import Ecto
    import Ecto.Changeset
    import Ecto.Query

    schema "model" do
      field :x, :integer
      field :y, :integer
      field :z, :integer
      field :w, {:array, :integer}

      has_many :comments, Tds.Ecto.TdsTest.Model2,
        references: :x,
        foreign_key: :z
      has_one :permalink, Tds.Ecto.TdsTest.Model3,
        references: :y,
        foreign_key: :id
    end
  end

  defmodule Model2 do
    use Ecto.Schema

    import Ecto
    import Ecto.Changeset
    import Ecto.Query

    schema "model2" do
      belongs_to :post, Tds.Ecto.TdsTest.Model,
        references: :x,
        foreign_key: :z
    end
  end

  defmodule Model3 do
    use Ecto.Schema

    import Ecto
    import Ecto.Changeset
    import Ecto.Query

    @schema_prefix "foo"
    schema "model3" do
      field :binary, :binary
    end
  end

  defp normalize(query, operation \\ :all) do
    {query, _params, _key} = Ecto.Query.Planner.prepare(query, operation, Tds.Ecto, 0)
    Ecto.Query.Planner.normalize(query, operation, Tds.Ecto, 0)
  end

  test "from" do
    query = Model |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.[x] FROM [model] AS m0}
  end

  test "from Model3 with schema foo" do
    query = Model3 |> select([r], r.binary) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.[binary] FROM [foo].[model3] AS m0}
  end

  test "from without model" do
    query = "model" |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.[x] FROM [model] AS m0}

    assert_raise Ecto.QueryError, ~r"TDS adapter requires a model", fn ->
      SQL.all from(p in "posts", select: p) |> normalize()
    end
  end
  test "from with schema source" do
    query = "public.posts" |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT p0.[x] FROM [public].[posts] AS p0}
  end
  test "from with schema source, linked database" do
    query = "externaldb.public.posts" |> select([r], r.x) |> normalize
    assert_raise ArgumentError, ~r"TDS addapter do not support query of external database or linked server table", fn ->
      SQL.all(query)
    end
  end

  test "select" do
    query = Model |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.[x], m0.[y] FROM [model] AS m0}

    query = Model |> select([r], [r.x, r.y]) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.[x], m0.[y] FROM [model] AS m0}
  end

  test "distinct" do
    query = Model |> distinct([r], true) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT DISTINCT m0.[x], m0.[y] FROM [model] AS m0}

    query = Model |> distinct([r], false) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.[x], m0.[y] FROM [model] AS m0}

    query = Model |> distinct(true) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT DISTINCT m0.[x], m0.[y] FROM [model] AS m0}

    query = Model |> distinct(false) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.[x], m0.[y] FROM [model] AS m0}

    assert_raise Ecto.QueryError, ~r"MSSQL does not allow expressions in distinct", fn ->
      query = Model |> distinct([r], [r.x, r.y]) |> select([r], {r.x, r.y}) |> normalize
      SQL.all(query)
    end
  end

  # test "where" do
  #   query = Model |> where([r], r.x == 42) |> where([r], r.y != 43) |> select([r], r.x) |> normalize
  #   assert SQL.all(query) == ~s{SELECT m0.[x] FROM [model] AS m0 WHERE (m0.[x] = 42) AND (m0.[y] != 43)}
  # end

  test "order by" do
    query = Model |> order_by([r], r.x) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.[x] FROM [model] AS m0 ORDER BY m0.[x]}

    query = Model |> order_by([r], [r.x, r.y]) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.[x] FROM [model] AS m0 ORDER BY m0.[x], m0.[y]}

    query = Model |> order_by([r], [asc: r.x, desc: r.y]) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.[x] FROM [model] AS m0 ORDER BY m0.[x], m0.[y] DESC}

    query = Model |> order_by([r], []) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.[x] FROM [model] AS m0}
  end

  test "limit and offset" do
    query = Model |> limit([r], 3) |> select([], 0) |> normalize
    assert SQL.all(query) == ~s{SELECT TOP(3) 0 FROM [model] AS m0}

    query = Model |> order_by([r], r.x) |> offset([r], 5) |> select([], 0) |> normalize
    assert_raise Ecto.QueryError, fn ->
      SQL.all(query)
    end

    query = Model |> order_by([r], r.x) |> offset([r], 5) |> limit([r], 3) |> select([], 0) |> normalize
    assert SQL.all(query) == ~s{SELECT 0 FROM [model] AS m0 ORDER BY m0.[x] OFFSET 5 ROW FETCH NEXT 3 ROWS ONLY}

    query = Model |> offset([r], 5) |> limit([r], 3) |> select([], 0) |> normalize
    assert_raise Ecto.QueryError, fn ->
      SQL.all(query)
    end
  end

  test "lock" do
    query = Model |> lock("WITH(NOLOCK)") |> select([], 0) |> normalize
    assert SQL.all(query) == ~s{SELECT 0 FROM [model] AS m0 WITH(NOLOCK)}
  end

  # # TODO
  # # These need to be updated
  # test "string escape" do
  #   query = Model |> select([], "'\\  ") |> normalize
  #   assert SQL.all(query) == ~s{SELECT '''\\\\  ' FROM [model] AS m0}

  #   query = Model |> select([], "'") |> normalize
  #   assert SQL.all(query) == ~s{SELECT '''' FROM [model] AS m0}
  # end

  test "binary ops" do
    query = Model |> select([r], r.x == 2) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.[x] = 2 FROM [model] AS m0}

    query = Model |> select([r], r.x != 2) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.[x] != 2 FROM [model] AS m0}

    query = Model |> select([r], r.x <= 2) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.[x] <= 2 FROM [model] AS m0}

    query = Model |> select([r], r.x >= 2) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.[x] >= 2 FROM [model] AS m0}

    query = Model |> select([r], r.x < 2) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.[x] < 2 FROM [model] AS m0}

    query = Model |> select([r], r.x > 2) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.[x] > 2 FROM [model] AS m0}
  end

  test "is_nil" do
    query = Model |> select([r], is_nil(r.x)) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.[x] IS NULL FROM [model] AS m0}

    query = Model |> select([r], not is_nil(r.x)) |> normalize
    assert SQL.all(query) == ~s{SELECT NOT (m0.[x] IS NULL) FROM [model] AS m0}
  end

  test "fragments" do
    query = Model
      |> select([r], fragment("lower(?)", r.x))
      |> normalize
    assert SQL.all(query) == ~s{SELECT lower(m0.[x]) FROM [model] AS m0}

    value = 13
    query = Model |> select([r], fragment("lower(?)", ^value)) |> normalize
    assert SQL.all(query) == ~s{SELECT lower(@1) FROM [model] AS m0}

    # query = Model |> select([], fragment(title: 2)) |> normalize
    # assert_raise ArgumentError, fn ->
    #   SQL.all(query)
    # end
  end

  test "literals" do
    query = Model |> select([], nil) |> normalize
    assert SQL.all(query) == ~s{SELECT NULL FROM [model] AS m0}

    query = Model |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 FROM [model] AS m0}

    query = Model |> select([], false) |> normalize
    assert SQL.all(query) == ~s{SELECT 0 FROM [model] AS m0}

    # query = Model |> select([], "abc") |> normalize
    # assert SQL.all(query) == ~s{SELECT 'abc' FROM [model] AS m0}

    query = Model |> select([], 123) |> normalize
    assert SQL.all(query) == ~s{SELECT 123 FROM [model] AS m0}

    query = Model |> select([], 123.0) |> normalize
    assert SQL.all(query) == ~s{SELECT 123.0 FROM [model] AS m0}
  end

  test "tagged type" do
    query = Model |> select([], type(^"601d74e4-a8d3-4b6e-8365-eddb4c893327", Ecto.UUID)) |> normalize
    assert SQL.all(query) == ~s{SELECT CAST(@1 AS uniqueidentifier) FROM [model] AS m0}
  end

  test "nested expressions" do
    z = 123
    query = from(r in Model, []) |> select([r], r.x > 0 and (r.y > ^(-z)) or true) |> normalize
    assert SQL.all(query) == ~s{SELECT ((m0.[x] > 0) AND (m0.[y] > @1)) OR 1 FROM [model] AS m0}
  end

  # test "in expression" do
  #   query = Model |> select([e], 1 in []) |> normalize
  #   assert SQL.all(query) == ~s{SELECT 0=1 FROM [model] AS m0}

  #   query = Model |> select([e], 1 in [1,e.x,3]) |> normalize
  #   assert SQL.all(query) == ~s{SELECT 1 IN (1,m0.[x],3) FROM [model] AS m0}

  #   query = Model |> select([e], 1 in ^[]) |> normalize
  #   # SelectExpr fields in Ecto v1 == [{:in, [], [1, []]}]
  #   # SelectExpr fields in Ecto v2 == [{:in, [], [1, {:^, [], [0, 0]}]}]
  #   assert SQL.all(query) == ~s{SELECT 0=1 FROM [model] AS m0}

  #   query = Model |> select([e], 1 in ^[1, 2, 3]) |> normalize
  #   assert SQL.all(query) == ~s{SELECT 1 IN (@1,@2,@3) FROM [model] AS m0}

  #   query = Model |> select([e], 1 in [1, ^2, 3]) |> normalize
  #   assert SQL.all(query) == ~s{SELECT 1 IN (1,@1,3) FROM [model] AS m0}
  # end

  # test "having" do
  #   query = Model |> having([p], p.x == p.x) |> select([p], p.x) |> normalize
  #   assert SQL.all(query) == ~s{SELECT m0.[x] FROM [model] AS m0 HAVING (m0.[x] = m0.[x])}

  #   query = Model |> having([p], p.x == p.x) |> having([p], p.y == p.y) |> select([p], [p.y, p.x]) |> normalize
  #   assert SQL.all(query) == ~s{SELECT m0.[y], m0.[x] FROM [model] AS m0 HAVING (m0.[x] = m0.[x]) AND (m0.[y] = m0.[y])}

  #   query = Model |> select([e], 1 in fragment("foo")) |> normalize
  #   assert SQL.all(query) == ~s{SELECT 1 IN (foo) FROM [model] AS m0}
  # end

  # test "group by" do
  #   query = Model |> group_by([r], r.x) |> select([r], r.x) |> normalize
  #   assert SQL.all(query) == ~s{SELECT m0.[x] FROM [model] AS m0 GROUP BY m0.[x]}

  #   query = Model |> group_by([r], 2) |> select([r], r.x) |> normalize
  #   assert SQL.all(query) == ~s{SELECT m0.[x] FROM [model] AS m0 GROUP BY 2}

  #   query = Model |> group_by([r], [r.x, r.y]) |> select([r], r.x) |> normalize
  #   assert SQL.all(query) == ~s{SELECT m0.[x] FROM [model] AS m0 GROUP BY m0.[x], m0.[y]}

  #   query = Model |> group_by([r], []) |> select([r], r.x) |> normalize
  #   assert SQL.all(query) == ~s{SELECT m0.[x] FROM [model] AS m0}
  # end

  # test "interpolated values" do
  #   query = Model
  #           |> select([], ^0)
  #           |> join(:inner, [], Model2, ^true)
  #           |> join(:inner, [], Model2, ^false)
  #           |> where([], ^true)
  #           |> where([], ^false)
  #           |> group_by([], ^1)
  #           |> group_by([], ^2)
  #           |> having([], ^true)
  #           |> having([], ^false)
  #           |> order_by([], fragment("?", ^3))
  #           |> order_by([], ^:x)
  #           |> limit([], ^4)
  #           |> offset([], ^5)
  #           |> normalize

  #   result =
  #     "SELECT TOP(@11) @1 FROM [model] AS m0 INNER JOIN [model2] AS m1 ON @2 " <>
  #     "INNER JOIN [model2] AS m2 ON @3 WHERE (@4) AND (@5) " <>
  #     "GROUP BY @6, @7 HAVING (@8) AND (@9) " <>
  #     "ORDER BY @10, m0.[x] OFFSET @12 ROW"

  #   assert SQL.all(query) == String.rstrip(result)
  # end

  # ## *_all

  # test "update all" do
  #   query = from(m in Model, update: [set: [x: 0]]) |> normalize(:update_all)
  #   assert SQL.update_all(query) ==
  #          ~s{UPDATE m0 SET m0.[x] = 0 FROM [model] AS m0}

  #   query = from(m in Model, update: [set: [x: 0], inc: [y: 1, z: -3]]) |> normalize(:update_all)
  #   assert SQL.update_all(query) ==
  #          ~s{UPDATE m0 SET m0.[x] = 0, m0.[y] = m0.[y] + 1, m0.[z] = m0.[z] + -3 FROM [model] AS m0}

  #   query = from(e in Model, where: e.x == 123, update: [set: [x: 0]]) |> normalize(:update_all)
  #   assert SQL.update_all(query) ==
  #          ~s{UPDATE m0 SET m0.[x] = 0 FROM [model] AS m0 WHERE (m0.[x] = 123)}

  #   # TODO:
  #   # nvarchar(max) conversion

  #   query = from(m in Model, update: [set: [x: 0, y: "123"]]) |> normalize(:update_all)
  #   assert SQL.update_all(query) ==
  #          ~s{UPDATE m0 SET m0.[x] = 0, m0.[y] = 123 FROM [model] AS m0}

  #   query = from(m in Model, update: [set: [x: ^0]]) |> normalize(:update_all)
  #   assert SQL.update_all(query) ==
  #          ~s{UPDATE m0 SET m0.[x] = @1 FROM [model] AS m0}

  #   query = Model |> join(:inner, [p], q in Model2, p.x == q.z)
  #                 |> update([_], set: [x: 0]) |> normalize(:update_all)
  #   assert SQL.update_all(query) ==
  #          ~s{UPDATE m0 SET m0.[x] = 0 FROM [model] AS m0 INNER JOIN [model2] AS m1 ON m0.[x] = m1.[z]}

  #   query = from(e in Model, where: e.x == 123, update: [set: [x: 0]],
  #                            join: q in Model2, on: e.x == q.z) |> normalize(:update_all)
  #   assert SQL.update_all(query) ==
  #          ~s{UPDATE m0 SET m0.[x] = 0 FROM [model] AS m0 } <>
  #          ~s{INNER JOIN [model2] AS m1 ON m0.[x] = m1.[z] WHERE (m0.[x] = 123)}
  # end

  # test "update all with prefix" do
  #   query = from(m in Model, update: [set: [x: 0]]) |> normalize(:update_all)
  #   assert SQL.update_all(%{query | prefix: "prefix"}) ==
  #          ~s{UPDATE m0 SET m0.[x] = 0 FROM [prefix].[model] AS m0}
  # end

  # test "delete all" do
  #   query = Model |> Queryable.to_query |> normalize
  #   assert SQL.delete_all(query) == ~s{DELETE m0 FROM [model] AS m0}

  #   query = from(e in Model, where: e.x == 123) |> normalize
  #   assert SQL.delete_all(query) ==
  #          ~s{DELETE m0 FROM [model] AS m0 WHERE (m0.[x] = 123)}

  #   query = Model |> join(:inner, [p], q in Model2, p.x == q.z) |> normalize
  #   assert SQL.delete_all(query) ==
  #          ~s{DELETE m0 FROM [model] AS m0 INNER JOIN [model2] AS m1 ON m0.[x] = m1.[z]}

  #   query = from(e in Model, where: e.x == 123, join: q in Model2, on: e.x == q.z) |> normalize
  #   assert SQL.delete_all(query) ==
  #          ~s{DELETE m0 FROM [model] AS m0 } <>
  #          ~s{INNER JOIN [model2] AS m1 ON m0.[x] = m1.[z] WHERE (m0.[x] = 123)}
  # end

  # test "delete all with prefix" do
  #   query = Model |> Queryable.to_query |> normalize
  #   assert SQL.delete_all(%{query | prefix: "prefix"}) ==
  #     ~s{DELETE m0 FROM [prefix].[model] AS m0}
  # end


  # ## Joins

  # test "join" do
  #   query = Model |> join(:inner, [p], q in Model2, p.x == q.z) |> select([], 0) |> normalize
  #   assert SQL.all(query) ==
  #          ~s{SELECT 0 FROM [model] AS m0 INNER JOIN [model2] AS m1 ON m0.[x] = m1.[z]}

  #   query = Model |> join(:inner, [p], q in Model2, p.x == q.z)
  #                 |> join(:inner, [], Model, true) |> select([], 0) |> normalize
  #   assert SQL.all(query) ==
  #          ~s{SELECT 0 FROM [model] AS m0 INNER JOIN [model2] AS m1 ON m0.[x] = m1.[z] } <>
  #          ~s{INNER JOIN [model] AS m2 ON 1}
  # end

  # test "join with nothing bound" do
  #   query = Model |> join(:inner, [], q in Model2, q.z == q.z) |> select([], 0) |> normalize
  #   assert SQL.all(query) ==
  #          ~s{SELECT 0 FROM [model] AS m0 INNER JOIN [model2] AS m1 ON m1.[z] = m1.[z]}
  # end

  # test "join without model" do
  #   query = "posts" |> join(:inner, [p], q in "comments", p.x == q.z) |> select([], 0) |> normalize
  #   assert SQL.all(query) ==
  #          ~s{SELECT 0 FROM [posts] AS p0 INNER JOIN [comments] AS c1 ON p0.[x] = c1.[z]}
  # end

  # test "join with prefix" do
  #   query = Model |> join(:inner, [p], q in Model2, p.x == q.z) |> select([], 0) |> normalize
  #   assert SQL.all(%{query | prefix: "prefix"}) ==
  #          ~s{SELECT 0 FROM [prefix].[model] AS m0 INNER JOIN [prefix].[model2] AS m1 ON m0.[x] = m1.[z]}
  # end

  # test "join with fragment" do
  #   query = Model
  #           |> join(:inner, [p], q in fragment("SELECT * FROM model2 AS m2 WHERE m2.id = ? AND m2.field = ?", p.x, ^10))
  #           |> select([p], {p.id, ^0})
  #           |> where([p], p.id > 0 and p.id < ^100)
  #           |> normalize
  #   assert SQL.all(query) ==
  #          ~s{SELECT m0.[id], @1 FROM [model] AS m0 INNER JOIN } <>
  #          ~s{(SELECT * FROM model2 AS m2 WHERE m2.id = m0.[x] AND m2.field = @2) AS f1 ON 1 } <>
  #          ~s{WHERE ((m0.[id] > 0) AND (m0.[id] < @3))}
  # end

  # ## Associations

  # test "association join belongs_to" do
  #   query = Model2 |> join(:inner, [c], p in assoc(c, :post)) |> select([], 0) |> normalize
  #   assert SQL.all(query) ==
  #          "SELECT 0 FROM [model2] AS m0 INNER JOIN [model] AS m1 ON m1.[x] = m0.[z]"
  # end

  # test "association join has_many" do
  #   query = Model |> join(:inner, [p], c in assoc(p, :comments)) |> select([], 0) |> normalize
  #   assert SQL.all(query) ==
  #          "SELECT 0 FROM [model] AS m0 INNER JOIN [model2] AS m1 ON m1.[z] = m0.[x]"
  # end

  # test "association join has_one" do
  #   query = Model |> join(:inner, [p], pp in assoc(p, :permalink)) |> select([], 0) |> normalize
  #   assert SQL.all(query) ==
  #          "SELECT 0 FROM [model] AS m0 INNER JOIN [model3] AS m1 ON m1.[id] = m0.[y]"
  # end

  # test "join produces correct bindings" do
  #   query = from(p in Model, join: c in Model2, on: true)
  #   query = from(p in query, join: c in Model2, on: true, select: {p.id, c.id})
  #   query = normalize(query)
  #   assert SQL.all(query) ==
  #          "SELECT m0.[id], m2.[id] FROM [model] AS m0 INNER JOIN [model2] AS m1 ON 1 INNER JOIN [model2] AS m2 ON 1"
  # end

  # # Model based

  # test "insert" do
  #   query = SQL.insert(nil, "model", [:x, :y], [])
  #   assert query == ~s{INSERT INTO [model] ([x], [y]) VALUES (@1, @2)}

  #   query = SQL.insert(nil, "model", [], [:id])
  #   assert query == ~s{INSERT INTO [model] OUTPUT INSERTED.[id] DEFAULT VALUES}

  #   query = SQL.insert(nil, "model", [], [])
  #   assert query == ~s{INSERT INTO [model] DEFAULT VALUES}

  #   query = SQL.insert("prefix", "model", [], [])
  #   assert query == ~s{INSERT INTO [prefix].[model] DEFAULT VALUES}
  # end

  # test "update" do
  #   query = SQL.update(nil, "model", [:id], [:x, :y], [])
  #   assert query == ~s{UPDATE [model] SET [id] = @1 WHERE [x] = @2 AND [y] = @3}

  #   query = SQL.update(nil, "model", [:x, :y], [:id], [:z])
  #   assert query == ~s{UPDATE [model] SET [x] = @1, [y] = @2 OUTPUT INSERTED.[z] WHERE [id] = @3}

  #   query = SQL.update("prefix", "model", [:x, :y], [:id], [])
  #   assert query == ~s{UPDATE [prefix].[model] SET [x] = @1, [y] = @2 WHERE [id] = @3}
  # end

  # test "delete" do
  #   query = SQL.delete(nil, "model", [:x, :y], [])
  #   assert query == ~s{DELETE FROM [model] WHERE [x] = @1 AND [y] = @2}

  #   query = SQL.delete(nil, "model", [:x, :y], [:z])
  #   assert query == ~s{DELETE FROM [model] OUTPUT DELETED.[z] WHERE [x] = @1 AND [y] = @2}

  #   query = SQL.delete("prefix", "model", [:x, :y], [])
  #   assert query == ~s{DELETE FROM [prefix].[model] WHERE [x] = @1 AND [y] = @2}
  # end

  # # DDL

  # import Ecto.Migration, only: [table: 1, table: 2, index: 2, index: 3, references: 1, references: 2]

  # test "executing a string during migration" do
  #   assert SQL.execute_ddl("example") == "example"
  # end

  # test "create table" do
  #   create = {:create, table(:posts),
  #              [{:add, :id, :serial, [primary_key: true]},
  #               {:add, :title, :string, []},
  #               {:add, :created_at, :datetime, []}]}
  #   assert SQL.execute_ddl(create) ==
  #          ~s|CREATE TABLE [posts] ([id] bigint NOT NULL PRIMARY KEY IDENTITY, [title] nvarchar(255) NULL, [created_at] datetime2 NULL)|
  # end

  # test "create table with prefix" do
  #   create = {:create, table(:posts, prefix: :foo),
  #              [{:add, :name, :string, [default: "Untitled", size: 20, null: false]},
  #               {:add, :price, :numeric, [precision: 8, scale: 2, default: {:fragment, "expr"}]},
  #               {:add, :on_hand, :integer, [default: 0, null: true]},
  #               {:add, :is_active, :boolean, [default: true]}]}

  #   assert SQL.execute_ddl(create) == """
  #   CREATE TABLE [foo].[posts] ([name] nvarchar(20) NOT NULL CONSTRAINT DF_name DEFAULT N'Untitled',
  #   [price] numeric(8,2) NULL CONSTRAINT DF_price DEFAULT expr,
  #   [on_hand] integer NULL CONSTRAINT DF_on_hand DEFAULT 0,
  #   [is_active] bit NULL CONSTRAINT DF_is_active DEFAULT 1)
  #   """ |> remove_newlines
  # end

  # test "create table with reference" do
  #   create = {:create, table(:posts),
  #              [{:add, :id, :serial, [primary_key: true]},
  #               {:add, :category_id, references(:categories), []} ]}
  #   assert SQL.execute_ddl(create) ==
  #          ~s|CREATE TABLE [posts] ([id] bigint NOT NULL PRIMARY KEY IDENTITY, [category_id] bigint NULL CONSTRAINT [posts_category_id_fkey] FOREIGN KEY (category_id) REFERENCES [categories]([id]))|
  # end

  # # I WANNA DIE
  # test "create table with composite key" do
	# 	create = {:create, table(:posts),
  #                [{:add, :a, :integer, [primary_key: true]},
  #                 {:add, :b, :integer, [primary_key: true]},
  #                 {:add, :name, :string, []}]}

  #     assert SQL.execute_ddl(create) == """
  #     CREATE TABLE [posts] ([a] bigint NULL, [b] bigint NULL, [name] nvarchar(255) NULL, PRIMARY KEY ([a], [b]))
  #     """ |> remove_newlines
  # end

  # test "create table with named reference" do
  #   create = {:create, table(:posts),
  #              [{:add, :id, :serial, [primary_key: true]},
  #               {:add, :category_id, references(:categories, name: :foo_bar), []} ]}
  #   assert SQL.execute_ddl(create) ==
  #          ~s|CREATE TABLE [posts] ([id] bigint NOT NULL PRIMARY KEY IDENTITY, [category_id] bigint NULL CONSTRAINT [foo_bar] FOREIGN KEY (category_id) REFERENCES [categories]([id]))|
  # end

  # test "create table with reference and on_delete: :nothing clause" do
  #   create = {:create, table(:posts),
  #              [{:add, :id, :serial, [primary_key: true]},
  #               {:add, :category_id, references(:categories, on_delete: :nothing), []} ]}
  #   assert SQL.execute_ddl(create) ==
  #          ~s|CREATE TABLE [posts] ([id] bigint NOT NULL PRIMARY KEY IDENTITY, [category_id] bigint NULL CONSTRAINT [posts_category_id_fkey] FOREIGN KEY (category_id) REFERENCES [categories]([id]))|
  # end

  # test "create table with reference and on_delete: :nilify_all clause" do
  #   create = {:create, table(:posts),
  #              [{:add, :id, :serial, [primary_key: true]},
  #               {:add, :category_id, references(:categories, on_delete: :nilify_all), []} ]}
  #   assert SQL.execute_ddl(create) ==
  #          ~s|CREATE TABLE [posts] ([id] bigint NOT NULL PRIMARY KEY IDENTITY, [category_id] bigint NULL CONSTRAINT [posts_category_id_fkey] FOREIGN KEY (category_id) REFERENCES [categories]([id]) ON DELETE SET NULL)|
  # end

  # test "create table with reference and on_delete: :delete_all clause" do
  #   create = {:create, table(:posts),
  #              [{:add, :id, :serial, [primary_key: true]},
  #               {:add, :category_id, references(:categories, on_delete: :delete_all), []} ]}
  #   assert SQL.execute_ddl(create) ==
  #          ~s|CREATE TABLE [posts] ([id] bigint NOT NULL PRIMARY KEY IDENTITY, [category_id] bigint NULL CONSTRAINT [posts_category_id_fkey] FOREIGN KEY (category_id) REFERENCES [categories]([id]) ON DELETE CASCADE)|  end

  # test "create table with column options" do
  #   create = {:create, table(:posts),
  #              [{:add, :name, :string, [default: "Untitled", size: 20, null: false]},
  #               {:add, :price, :numeric, [precision: 8, scale: 2, default: {:fragment, "expr"}]},
  #               {:add, :on_hand, :integer, [default: 0, null: true]},
  #               {:add, :is_active, :boolean, [default: true]}]}

  #   assert SQL.execute_ddl(create) == """
  #   CREATE TABLE [posts] ([name] nvarchar(20) NOT NULL
  #   CONSTRAINT DF_name DEFAULT N'Untitled',
  #   [price] numeric(8,2) NULL
  #   CONSTRAINT DF_price DEFAULT expr,
  #   [on_hand] integer NULL
  #   CONSTRAINT DF_on_hand DEFAULT 0,
  #   [is_active] bit NULL
  #   CONSTRAINT DF_is_active DEFAULT 1)
  #   """ |> remove_newlines
  # end

  # test "drop table" do
  #   drop = {:drop, table(:posts)}
  #   assert SQL.execute_ddl(drop) == ~s|DROP TABLE [posts]|
  # end

  # test "drop table with prefixes" do
  #   drop = {:drop, table(:posts, prefix: :foo)}
  #   assert SQL.execute_ddl(drop) == ~s|DROP TABLE [foo].[posts]|
  # end

  # test "alter table" do
  #   alter = {:alter, table(:posts),
  #              [{:add, :title, :string, [default: "Untitled", size: 100, null: false]},
  #               {:modify, :price, :numeric, [precision: 8, scale: 2]},
  #               {:remove, :summary}]}

  #   assert SQL.execute_ddl(alter) == """
  #   ALTER TABLE [posts] ADD [title] nvarchar(100) NOT NULL ;
  #   IF (OBJECT_ID('DF_title', 'D') IS NOT NULL)
  #   BEGIN
  #   ALTER TABLE [posts] DROP CONSTRAINT DF_title
  #   END;
  #   ALTER TABLE [posts] ADD CONSTRAINT DF_title DEFAULT N'Untitled' FOR [title];
  #   ALTER TABLE [posts] ALTER COLUMN [price] numeric(8,2) NULL ;
  #   IF (OBJECT_ID('DF_price', 'D') IS NOT NULL)
  #   BEGIN
  #   ALTER TABLE [posts] DROP CONSTRAINT DF_price
  #   END;
  #   ALTER TABLE [posts] DROP COLUMN [summary]
  #   """ |> remove_newlines
  # end

  # test "alter table with prefix" do
  #   alter = {:alter, table(:posts, prefix: :foo),
  #            [{:add, :title, :string, [default: "Untitled", size: 100, null: false]},
  #             {:add, :author_id, references(:author), []},
  #             {:modify, :price, :numeric, [precision: 8, scale: 2, null: true]},
  #             {:modify, :cost, :integer, [null: true, default: nil]},
  #             {:modify, :permalink_id, references(:permalinks, prefix: :foo), null: false},
  #             {:remove, :summary}]}

  #   expected_ddl =
  #   # add title column
  #   "ALTER TABLE [foo].[posts] " <>
  #     "ADD [title] nvarchar(100) NOT NULL " <>
  #     "CONSTRAINT [DF_posts_title] DEFAULT N'Untitled';" <>
  #   # add author_id column and reference author
  #   "ALTER TABLE [foo].[posts] " <>
  #     "ADD [author_id] bigint NULL " <>
  #     "CONSTRAINT [FK_posts_author_id] " <>
  #     "FOREIGN KEY ([author_id]) REFERENCES [author]([id]);" <>
  #   # modify price
  #   "IF (OBJECT_ID('DF_posts_price', 'D') IS NOT NULL) BEGIN " <>
  #     "ALTER TABLE [foo].[posts] DROP CONSTRAINT [DF_posts_price] END;" <>
  #   "ALTER TABLE [foo].[posts] " <>
  #     "ALTER COLUMN [price] decimal(8,2)"
  #   # modify cost
  #   "IF (OBJECT_ID('DF_posts_cost', 'D') IS NOT NULL) BEGIN " <>
  #     "ALTER TABLE [foo].[posts] DROP CONSTRAINT [DF_post_cost] END;" <>
  #   "ALTER TABLE [foo].[posts] " <>
  #     "ALTER COLUMN [cost] integer NOT NULL;" <>
  #   "ALTER TABLE [foo].[posts] "<>
  #     "ADD CONSTRAINT [DF_posts_cost] DEFAULT NULL FOR [cost];" <>
  #   # modify permalink_id and refence permalinks in schema foo
  #   "IF (OBJECT_ID('[FK_posts_permalink_id]', 'F') IS NOT NULL) BEGIN" <>
  #     " ALTER TABLE [foo].[posts] DROP CONSTRAINT [FK_posts_permalink_id] END;" <>
  #   "IF (OBJECT_ID('[DF_permalink_id]', 'D') IS NOT NULL) BEGIN" <>
  #     " ALTER TABLE [foo].[posts] DROP CONSTRAINT [DF_permalink_id] END;" <>
  #   "ALTER TABLE [foo].[posts] " <>
  #     "ALTER COLUMN [permalink_id] bigint NOT NULL;" <>
  #   "ALTER TABLE [foo].[posts] " <>
  #     "ADD CONSTRAINT [FK_posts_permalink_id] FOREIGN KEY ([permalink_id]) REFERENCES [foo].[permalinks]([id])" <>
  #   # remove summary
  #   "ALTER TABLE [foo].[posts] DROP COLUMN [summary]"

  #   assert SQL.execute_ddl(alter)  == expected_ddl |> remove_newlines
  # end

  # test "alter table with reference" do
  #   alter = {:alter, table(:posts),
  #              [{:add, :comment_id, references(:comments), []}]}

  #   assert SQL.execute_ddl(alter) == """
  #   ALTER TABLE [posts] ADD [comment_id] bigint NULL CONSTRAINT [posts_comment_id_fkey] FOREIGN KEY (comment_id) REFERENCES [comments]([id])
  #   """ |> remove_newlines
  # end

  # test "alter table with adding foreign key constraint" do
  #   alter = {:alter, table(:posts),
  #             [{:modify, :user_id, references(:users, on_delete: :delete_all), []}]
  #           }

  #   assert SQL.execute_ddl(alter) == """
  #   ALTER TABLE [posts] ALTER COLUMN [user_id] bigint NULL ;
  #   IF (OBJECT_ID('[posts_user_id_fkey]', 'F') IS NOT NULL)
  #   BEGIN
  #   ALTER TABLE [posts] DROP CONSTRAINT [posts_user_id_fkey]
  #   END;
  #   ALTER TABLE [posts] ADD CONSTRAINT [posts_user_id_fkey] FOREIGN KEY ([user_id]) REFERENCES [users]([id]) ON DELETE CASCADE ;
  #   IF (OBJECT_ID('DF_user_id', 'D') IS NOT NULL)
  #   BEGIN
  #   ALTER TABLE [posts] DROP CONSTRAINT DF_user_id
  #   END
  #   """ |> remove_newlines
  # end

  # test "create table with options" do
  #   create = {:create, table(:posts, [options: "WITH FOO=BAR"]),
  #              [{:add, :id, :serial, [primary_key: true]},
  #               {:add, :created_at, :datetime, []}]}
  #   assert SQL.execute_ddl(create) ==
  #          ~s|CREATE TABLE [posts] ([id] bigint NOT NULL PRIMARY KEY IDENTITY, [created_at] datetime2 NULL) WITH FOO=BAR|
  # end

  # test "rename table" do
  #   rename = {:rename, table(:posts), table(:new_posts)}
  #   assert SQL.execute_ddl(rename) == ~s|EXEC sp_rename 'posts', 'new_posts'|
  # end

  # test "rename table with prefix" do
  #   rename = {:rename, table(:posts, prefix: :foo), table(:new_posts, prefix: :foo)}
  #   assert SQL.execute_ddl(rename) == ~s|EXEC sp_rename 'foo.posts', 'foo.new_posts'|
  # end

  # test "rename column" do
  #   rename = {:rename, table(:posts), :given_name, :first_name}
  #   assert SQL.execute_ddl(rename) == ~s|EXEC sp_rename 'posts.given_name', 'first_name', 'COLUMN'|
  # end

  # test "rename column in table with prefixes" do
  #   rename = {:rename, table(:posts, prefix: :foo), :given_name, :first_name}
  #   assert SQL.execute_ddl(rename) == ~s|EXEC sp_rename 'foo.posts.given_name', 'first_name', 'COLUMN'|
  # end

  # test "create index" do
  #   create = {:create, index(:posts, [:category_id, :permalink])}
  #   assert SQL.execute_ddl(create) ==
  #          ~s|CREATE INDEX [posts_category_id_permalink_index] ON [posts] ([category_id], [permalink])|

  #   create = {:create, index(:posts, ["lower(permalink)"], name: "posts$main")}
  #   assert SQL.execute_ddl(create) ==
  #          ~s|CREATE INDEX [posts$main] ON [posts] ([lower(permalink)])|
  # end

  # test "create index with prefix" do
  #   create = {:create, index(:posts, [:category_id, :permalink], prefix: :foo)}
  #   assert SQL.execute_ddl(create) ==
  #          ~s|CREATE INDEX [posts_category_id_permalink_index]  ON  [foo].[posts]  (category_id, permalink)|
  # end

  # test "create index asserting concurrency" do
  #   create = {:create, index(:posts, ["lower(permalink)"], name: "posts$main", concurrently: true)}
  #   assert SQL.execute_ddl(create) ==
  #          ~s|CREATE INDEX `posts$main` ON `posts` (`lower(permalink)`) LOCK=NONE|
  # end

  # test "create unique index" do
  #   create = {:create, index(:posts, [:permalink], unique: true)}
  #   assert SQL.execute_ddl(create) ==
  #          ~s|CREATE UNIQUE INDEX `posts_permalink_index` ON `posts` (`permalink`)|
  # end

  # test "create an index using a different type" do
  #   create = {:create, index(:posts, [:permalink], using: :hash)}
  #   assert SQL.execute_ddl(create) ==
  #          ~s|CREATE INDEX `posts_permalink_index` ON `posts` (`permalink`) USING hash|
  # end

  # test "drop index" do
  #   drop = {:drop, index(:posts, [:id], name: "posts$main")}
  #   assert SQL.execute_ddl(drop) == ~s|DROP INDEX `posts$main` ON `posts`|
  # end

  # test "drop index with prefix" do
  #   drop = {:drop, index(:posts, [:id], name: "posts_category_id_permalink_index", prefix: :foo)}
  #   assert SQL.execute_ddl(drop) == ~s|DROP INDEX [posts_category_id_permalink_index]  ON  [foo].[posts]|
  # end

  # test "drop index asserting concurrency" do
  #   drop = {:drop, index(:posts, [:id], name: "posts$main", concurrentlyrently: true)}
  #   assert SQL.execute_ddl(drop) == ~s|DROP INDEX `posts$main` ON `posts` LOCK=NONE|
  # end



  # defp remove_newlines(string) do
  #   string |> String.strip |> String.replace("\n", " ")
  # end

end
