## 📚 Public APIs

The api docs are not enough yet, but you can read the code to understand how to use the public APIs.

### Modules

#### `witch-line.core.statusline`

This module provides functions to manage and manipulate the statusline values and rendering.

- `render(max_width)`: Renders the statusline with a specified maximum width.

  - `max_width`: The maximum width for the statusline rendering.

- `set(index, value, hl_name)`: Sets the value and optional highlight for a specific index in the statusline.

  - `index`: The index of the component to set.
  - `value`: The value to set for the component.
  - `hl_name`: (Optional) The highlight group name to assign to the component.

- `bulk_set(indices, value, hl_name)`: Sets the same value and optional highlight for multiple indices in the statusline.

  - `indices`: A list of indices of the components to set.
  - `value`: The value to set for the specified components.
  - `hl_name`: (Optional) The highlight group name to assign to the specified components.

- `bulk_set_sep(indices, adjust, value, hl_name)`: Sets the separator value and optional highlight for multiple indices with an adjustment.

  - `indices`: A list of indices of the components to set the separator for.
  - `adjust`: An adjustment value to apply to each index (e.g., -1 for left separator, +1 for right separator).
  - `value`: The separator value to set for the specified components.
  - `hl_name`: (Optional) The highlight group name to assign to the specified components.

#### `witch-line.core.handler`

This module handles the setup and management of statusline components.

- `DepStoreKey`: A enum defining keys for dependency storage.

- `refresh_component_graph(comp, dep_store_ids, seen)`: Updates the component state and its dependencies then rerenders the statusline.

  - `comp`: The component to refresh along with its dependencies.
  - `dep_store_ids`: A list of dependency store IDs to refresh.
  - `seen`: A set of already processed components to avoid infinite loops.

- `update_component(comp, session_id)`: Updates the value and style of a specific component but does not rerender the statusline.

  - `comp`: The component to update.
  - `session_id`: The session identifier for the current update.

- `update_comp_graph(comp, session_id, dep_store_ids, seen)`: Recursively updates a component and all its dependent components, then rerenders the statusline.

  - `comp`: The component to update along with its dependencies.
  - `session_id`: The session identifier for the current update.
  - `dep_store_ids`: A list of dependency store IDs to update.
  - `seen`: A set of already processed components to avoid infinite loops.

- `update_comp_graph_by_ids = function(ids, session_id, dep_store_ids, seen)`: Updates components by their IDs along with their dependencies, then rerenders the statusline.

  - `ids`: A list of component IDs to update.
  - `session_id`: The session identifier for the current update.
  - `dep_store_ids`: A list of dependency store IDs to update.
  - `seen`: A set of already processed components to avoid infinite loops.

- `register_abstract_component(comp)`: Registers an abstract component that can be used as a base for other components.

  - `comp`: The abstract component to register.

- `register_combined_component(comp, parent_id)`: Registers a combined component that inherits properties from a parent component.

  - `comp`: The combined component to register.
  - `parent_id`: The ID of the parent component to inherit from.
