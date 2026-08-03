# Filters, ordering and pagination

- Filter with the string DSL:
  `?filter=and(gte(age,18),icontains(name,ada))`. Operators (lowercase,
  exact): `eq contains icontains startswith istartswith endswith iendswith lt
  lte gt gte in isnull`; combinators `and or not`. Dots traverse links:
  `eq(customer.name,Ada)`. `in` takes parens: `in(role,(admin,editor))`.
- Order with `?order[]=param;asc` or `param;desc` — any other direction word
  raises (500). An order string without `;` silently breaks the query. Dotted
  paths are supported.
- Paginate with `?offset=&limit=`.
- ALWAYS pass an explicit `?limit=` to `GET /lib/unit` (global search) — the
  request crashes without it.
- `?load_links=`, `?load_values=`, `?load_files=` must be exactly the string
  `true`:

  ```
  GET /lib/person/unit?load_links=true     # works
  GET /lib/person/unit?load_links=1        # silently ignored
  ```

  `?count_only=` is the inconsistent one: it accepts `true`, `True` and `1`.
- Link walks: `GET /lib/:arke_id/unit/:unit_id/link/:direction` where
  direction is exactly `child` or `parent` (anything else → 500), with
  `?depth=` and `?link_type=`.
- Client filters (`?filter=`) and permission filters are ANDed — unexpectedly
  empty results usually mean the permission filter intersected everything
  away.
- Avoid the geo bounding-box filter (`?latitude=&longitude=&radius=`) until
  fixed: coordinates without a decimal point raise, and the box math is wrong.
