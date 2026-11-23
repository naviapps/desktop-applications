func firstValueTask<Element>(
  from stream: AsyncStream<Element>
) -> Task<Element?, Never> {
  Task {
    for await value in stream {
      return value
    }
    return nil
  }
}
