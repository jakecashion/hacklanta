import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { Button, Card } from "../components/brut";
import { TopBar } from "../components/Layouts";
import { useStore } from "../state/store";

/** Developer tools for poking the mock state. Open it with the wrench button on the map. */
export function DevMenu() {
  const navigate = useNavigate();
  const { users, isBlocked, block, unblock, addSamples, clearRecommendations, receiveSong, resetBlocks } = useStore();
  const [personId, setPersonId] = useState(users[0].id);
  const person = users.find((u) => u.id === personId) ?? users[0];
  const blocked = isBlocked(person.id);

  return (
    <div className="page">
      <TopBar title="dev menu" />
      <div className="stack content narrow">
        <Card flat className="col gap12 pad16">
          <h3>test person</h3>
          <div className="input">
            <select className="select" value={personId} onChange={(e) => setPersonId(e.target.value)} aria-label="person">
              {users.map((u) => <option key={u.id} value={u.id}>{u.name}</option>)}
            </select>
          </div>
          <Button
            variant="ghost"
            onClick={() => (blocked ? unblock(person.id) : block(person.id, person.name))}
          >
            {blocked ? `unblock ${person.name}` : `block ${person.name}`}
          </Button>
          <Button variant="ghost" onClick={resetBlocks}>unblock everyone</Button>
        </Card>

        <Card flat className="col gap12 pad16">
          <h3>playlist</h3>
          <Button variant="ghost" onClick={() => receiveSong(person.id)}>receive a song from {person.name}</Button>
          <Button variant="ghost" onClick={addSamples}>add 3 sample songs</Button>
          <Button variant="ghost" onClick={clearRecommendations}>clear playlist</Button>
        </Card>

        <Card flat className="col gap12 pad16">
          <h3>match flow</h3>
          <Button onClick={() => navigate(`/match/${person.id}`)} disabled={blocked}>open match screen now</Button>
          <Button variant="ghost" onClick={() => navigate(`/match/${person.id}?out=1`)} disabled={blocked}>
            open match screen (out of range)
          </Button>
          {blocked && <p className="small muted">{person.name} is blocked.</p>}
        </Card>
      </div>
    </div>
  );
}
