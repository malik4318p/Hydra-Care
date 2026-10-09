export function validate(schema, source = 'body') {
  return (req, res, next) => {
    const result = schema.safeParse(req[source]);

    if (!result.success) {
      const message = result.error.issues
        .map((issue) => `${issue.path.join('.') || source}: ${issue.message}`)
        .join('; ');

      return res.status(400).json({ success: false, message });
    }

    if (source === 'body') {
      req.body = result.data;
    } else {
      // req.query / req.params may not be reassignable directly in some
      // Express versions, so merge the validated values in place instead.
      Object.assign(req[source], result.data);
    }

    next();
  };
}
