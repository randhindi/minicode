interface User {
  id: number;
  name?: string;
}

type Result<T> = { ok: true; value: T } | { ok: false; error: Error };

@Injectable()
export class UserService {
  private readonly cache = new Map<number, User>();

  async find(id: number): Promise<Result<User>> {
    const user = this.cache.get(id) satisfies User | undefined;
    return user ? { ok: true, value: user } : { ok: false, error: new Error("missing") };
  }
}
