## 📚 Public APIs

The api docs are not enough yet, but you can read the code to understand how to use the public APIs.

## Module `witch-line.core.statusline`

This module provides functions to manage and manipulate the statusline values and rendering.

- `render(max_width)`: Renders the statusline with a specified maximum width.

  - `max_width`: The maximum width for the statusline rendering.

## Module `witch-line.core.handler`

This module handles the setup and management of statusline components.

- `refresh_component_graph(comp, dep_graph_kind, seen)`: Updates the component state and its dependencies then rerenders the statusline.

  - `comp`: The component to refresh along with its dependencies.
  - `dep_graph_kind`: Optional. A list of dependency store IDs to refresh. (Defaults to Timer and Event)
  - `seen`: A set of already processed components to avoid infinite loops.

- `update_comp(comp, sid)`: Updates the value and style of a specific component but does not rerender the statusline.

  - `comp`: The component to update.
  - `sid`: The session identifier for the current update.

- `update_comp_graph(comp, sid, dep_graph_kind, seen)`: Recursively updates a component and all its dependent components, then rerenders the statusline.

  - `comp`: The component to update along with its dependencies.
  - `sid`: The session identifier for the current update.
  - `dep_graph_kind`: A list of dependency store IDs to update.
  - `seen`: A set of already processed components to avoid infinite loops.

- `update_comp_graph_by_ids = function(ids, sid, dep_graph_kind, seen)`: Updates components by their IDs along with their dependencies, then rerenders the statusline.

  - `ids`: A list of component IDs to update.
  - `sid`: The session identifier for the current update.
  - `dep_graph_kind`: A list of dependency store IDs to update.
  - `seen`: A set of already processed components to avoid infinite loops.

- `register_abstract_component(comp)`: Registers an abstract component that can be used as a base for other components.

  - `comp`: The abstract component to register.

- `register_combined_component(comp, parent_id)`: Registers a combined component that inherits properties from a parent component.

  - `comp`: The combined component to register.
  - `parent_id`: The ID of the parent component to inherit from.

## Module `witch-line.core.Session`

This module provides functions to manage sessions for the statusline.

- `new(): sid` : Creates a new session instance.

- `remove(sid)`: Removes the current session instance.

  - `sid`: The session identifier to remove.

- `with_session(sid, fn)`: Executes a function within the context of a specific session.

  - `sid`: The session identifier to use.
  - `fn`: The function to execute within the session context.

- `new_store(sid, store_id, initial_value)`: Creates a new store for a specific session.

  - `sid`: The session identifier.
  - `store_id`: The identifier for the store.
  - `initial_value`: The initial value for the store.

- `get_store(sid, store_id)`: Retrieves the value of a specific store for a session.

  - `sid`: The session identifier.
  - `store_id`: The identifier for the store.
